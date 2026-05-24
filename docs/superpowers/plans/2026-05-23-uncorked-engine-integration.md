# Crosswire Engine Integration — Implementation Plan

**Date:** 2026-05-22
**Status:** Final implementation plan (revised after three design-review passes)
**Audience:** Claude Code, running on nick-dev-01, working in the Crosswire repo

## Vision

Crosswire is a complete, standalone macOS app for running Windows software. The engine is an
internal implementation detail: not a user-facing concept, not a download, not a separate
product. Users install Crosswire, it works.

There is no "Wine" in Crosswire. There is no "engine" visible to users. There is only Crosswire.

## Distribution Decision

Crosswire ships as a **DMG only**, for both first install and updates. The PKG idea is dropped.

Rationale:
- A compressed DMG and a PKG payload of the same app are within a few MB of each other, so
  PKG offers no download-size benefit. The size lever is the engine payload, not the container.
- The only real PKG advantage (postinstall scripts, installing outside the app bundle) is not
  used: the engine ships pre-extracted inside the app bundle, so the PKG would do nothing but
  copy the app, which drag-to-Applications already does.
- A single artifact means one build path shared by first install and Sparkle updates, half the
  signing and notarization surface, and one thing to test.
- In Phase 1 an unsigned PKG adds a second Gatekeeper prompt; a DMG does not.

The Mac App Store is **explicitly out of scope** (see Out of Scope). The end-state goal is
Developer ID signing plus notarization, which delivers the full trusted, no-friction, auto
updating experience without the App Store.

## What We Are Building

- The engine ships pre-extracted inside the app bundle, signed at build time.
- A DMG containing a fully built, signed `Crosswire.app` is the one and only distribution artifact.
- The app opens cold, the engine is already present, nothing to download.
- Updates arrive as new Crosswire versions via Sparkle (DMG).
- New upstream engine builds are detected automatically and queued as draft releases.

## Engine Location Inside the App

The engine is placed inside the app bundle **after `xcodebuild` builds the app** and **before
the app bundle is re-sealed**. It is never extracted at install time.

```
Crosswire.app/
  Contents/
    Resources/
      Engine/
        bin/
          Crosswire64       <- wrapper script -> wine64
          Crosswireserver   <- wrapper script -> wineserver
          Crosswireboot     <- wrapper script -> wineboot
          wine64           <- Gcenx binary (internal only)
          wineserver       <- Gcenx binary (internal only)
          wineboot         <- Gcenx binary (internal only)
          [other binaries]
        lib/               <- contains Mach-O .dylib AND Mach-O .so files
        share/
      CrosswireEngineVersion.plist   <- build-generated, records upstream tag for diagnostics
```

Because the engine is inserted and signed before the outer bundle is sealed, Phase 2 signing
and notarization work without rearchitecting. The Phase 2 changes are described honestly in the
Signing Roadmap; they are not a pure credentials swap.

## Wrapper Scripts

Gcenx binaries cannot be renamed without recompiling Wine from source, because they reference
each other internally by name. Wrapper scripts provide Crosswire-named entry points:

```sh
#!/bin/sh
exec "$(dirname "$0")/wine64" "$@"
```

`Crosswire64`, `Crosswireserver`, `Crosswireboot` are thin wrappers of this form. Constraints:

- All Swift code in CrosswireKit calls `Crosswire64` only. `wine64` is never referenced in app code.
- Swift must invoke the wrapper by **absolute path** (resolved from `CrosswireEngine.binFolder`),
  so `$(dirname "$0")` inside the wrapper always resolves to the real `Engine/bin` directory.
- The wrappers have no file extension. They are shell scripts and cannot be Mach-O code-signed.
  The signing script must detect this by content (see Signing), not by filename.

## Signing — Correct Procedure

`codesign --force --deep` must NOT be used. `--deep` is deprecated, unreliable for nested
binaries, and does not correctly sign independent executables in a flat directory. On Apple
Silicon every Mach-O image must carry a valid signature (ad-hoc is sufficient in Phase 1) or it
is killed on launch or load.

### What must be signed

The signing script must sign **every Mach-O file anywhere under `Engine/`**, detected with
`file`, not by extension or directory. This specifically includes:
- `.dylib` libraries anywhere under `Engine/`.
- Mach-O `.so` files under `lib/wine/` (the Unix-side Wine builtins). These are Mach-O on
  macOS and were missed by earlier drafts that only signed `*.dylib`.
- Mach-O executables under `bin/` and anywhere else.

It must skip non-Mach-O files: the wrapper shell scripts, Wine's PE-format `.dll` files (those
are Windows binaries Wine loads itself), and data files.

### `scripts/sign-engine.sh`

```bash
#!/bin/bash
# Signs every Mach-O file under the engine, inside-out.
# Phase 1 (ad-hoc):       IDENTITY=-   (RUNTIME and ENTITLEMENTS unset)
# Phase 2 (Developer ID): IDENTITY="Developer ID Application: NAME (TEAMID)"
#                         RUNTIME="--options runtime --timestamp"
#                         ENTITLEMENTS="scripts/engine.entitlements"
set -euo pipefail

ENGINE="$1"                      # path to Crosswire.app/Contents/Resources/Engine
IDENTITY="${IDENTITY:--}"
RUNTIME="${RUNTIME:-}"
ENTITLEMENTS="${ENTITLEMENTS:-}"

runtime_args=()
[[ -n "$RUNTIME" ]] && runtime_args=($RUNTIME)
ent_args=()
[[ -n "$ENTITLEMENTS" ]] && ent_args=(--entitlements "$ENTITLEMENTS")

while IFS= read -r f; do
  desc="$(file -b "$f")"
  if [[ "$desc" == *Mach-O*executable* ]]; then
    # Process entry points. Entitlements are applied here in Phase 2.
    codesign --force --sign "$IDENTITY" "${runtime_args[@]}" "${ent_args[@]}" "$f"
  elif [[ "$desc" == *Mach-O* ]]; then
    # Libraries (.dylib, .so): hardened runtime in Phase 2, no entitlements.
    codesign --force --sign "$IDENTITY" "${runtime_args[@]}" "$f"
  fi
  # Non-Mach-O files (shell wrappers, PE .dll, data) are skipped.
done < <(find "$ENGINE" -type f)
```

The outer `Crosswire.app` is signed last, by the pipeline, after this script runs. That final
`codesign --force` on the app re-seals the bundle and brings the freshly inserted engine under
the app's signature.

## Build Pipeline

### Trigger

`engine-update-check.yml` (renamed from `wine-update-check.yml`) runs weekly on a macOS runner.
It reads the currently bundled upstream tag from the committed repo marker file
`engine-version.txt`, queries the latest Gcenx release tag, and if they differ it triggers
`engine-bundle.yml`. The marker file is the CI source of truth; nothing else records the
bundled engine version on the repo side.

### `engine-bundle.yml` steps

The ordering below is correct: the app bundle does not exist until `xcodebuild` runs, so the
engine cannot be inserted before that.

1. Read the current bundled tag from `engine-version.txt`.
2. Query the latest Gcenx release via the GitHub API; select the asset by priority (table below).
3. If the latest tag equals the marker, stop. Otherwise continue.
4. Download the selected `.tar.xz`.
5. Extract it and rename the top-level directory to `Engine/`.
6. Generate wrapper scripts (`Crosswire64`, `Crosswireserver`, `Crosswireboot`) in `Engine/bin/`
   via `scripts/generate-wrappers.sh`, with `chmod +x`.
7. Bump the Crosswire version (patch bump for an engine-only update). Update `engine-version.txt`
   and regenerate the in-bundle `CrosswireEngineVersion.plist` resource with the new upstream tag.
8. Build `Crosswire.app` via `xcodebuild`. At this point `xcodebuild` signs the app's own code
   and bundled frameworks (for example Sparkle); the engine is not yet present.
9. Copy the prepared `Engine/` into `Crosswire.app/Contents/Resources/Engine/`.
10. Run `scripts/sign-engine.sh` against `Crosswire.app/Contents/Resources/Engine` to sign every
    Mach-O file in the engine.
11. Re-sign the outer `Crosswire.app` bundle (`codesign --force`, with the app entitlements).
    This re-seals the bundle so the engine is covered by the app signature.
12. Phase 2 only: notarize the app and staple the ticket.
13. Build the DMG containing `Crosswire.app`.
14. Phase 2 only: notarize the DMG and staple the ticket.
15. Verify: `codesign --verify --strict Crosswire.app`, and in Phase 2 `spctl --assess --type exec`.
16. Commit the version bump and updated `engine-version.txt` to a release branch. Create a
    **draft** GitHub release with the DMG attached.
17. Open a GitHub issue noting the draft is ready for testing.

A human tests the draft, then publishes. The Sparkle appcast is then updated to point to the
new DMG.

`release.yml` is updated to use the same build, sign, DMG, and notarize steps (factor them into
a reusable workflow or composite action shared with `engine-bundle.yml`, so there is one
implementation). The old PKG and any alternate DMG path are removed. There is one artifact.

### Upstream Asset Priority

| Priority | Asset name |
|----------|-----------|
| 1 | `wine-stable-*` (if Gcenx restores it) |
| 2 | `wine-staging-*` |
| 3 | `wine-devel-*` |
| 4 | any `.tar.xz` |

## Version Mapping

Crosswire's version is fully decoupled from the engine version. The engine version never appears
in Crosswire's version string, since that would leak an internal detail.

- Engine-only updates increment Crosswire's **patch** version (1.0.2 to 1.0.3).
- App feature or fix releases increment patch or minor as appropriate.
- The upstream engine tag (for example `11.9`) is recorded in two places: `engine-version.txt`
  at the repo root (the CI marker) and `CrosswireEngineVersion.plist` inside the app bundle
  (build-generated, read by the app for diagnostics and support tooling only). There is no copy
  in Application Support.

## Code Changes in Crosswire

### Deleted

- `Crosswire/Views/Setup/CrosswireWineDownloadView.swift` (the runtime download screen).
- All Gcenx GitHub API calls from within the running app.
- The setup and onboarding flow that gated the app behind an engine download.
- All `CrosswireWineInstaller` install and download logic (the engine is pre-bundled).

### Renamed

| Old | New |
|-----|-----|
| `CrosswireWineInstaller` | `CrosswireEngine` |
| `CrosswireWineVersion` | `CrosswireEngineVersion` |
| `isCrosswireWineInstalled()` | `isEnginePresent()` (see note below) |
| `CrosswireWineVersion()` | `engineVersion()` |
| `binFolder` path | `Bundle.main.resourceURL/Engine/bin` |
| `CrosswireKit/.../CrosswireWine/` directory | `CrosswireKit/.../Engine/` |

### Updated

- `CrosswireEngine.binFolder` resolves to `Crosswire.app/Contents/Resources/Engine/bin`.
- All process launches reference `Crosswire64` by absolute path, never `wine64`.
- No user-facing strings mention Wine, engine, or internal version numbers.
- `UncorkError` and related error types reviewed for any Wine naming.
- `isEnginePresent()` is now an **integrity check**, not a download trigger. With a bundled
  engine it should normally always be true; if it returns false the install is corrupt, so the
  app shows an error directing the user to reinstall, rather than trying to download anything.

### Added: one-time migration cleanup

Users upgrading from a download-based build have a stale engine (~600MB) left in Application
Support. On first launch of the new version, detect and delete only that stale engine
directory. **Do not delete bottles or wineprefixes**, which also live under Application Support
and must be preserved. This runs once and is a no-op for new installs.

### Kept

- All bottle management (Bottle, BottleSettings, BottleData).
- All program launching logic (Program, ProgramSettings).
- DXVK, winetricks, Rosetta2 utilities.
- PE binary parsing.
- All existing UI views except the deleted setup and download flow.

## Signing Roadmap

### Phase 1 (no Developer ID yet)

- Engine binaries: ad-hoc signed individually via `sign-engine.sh` with `IDENTITY=-` and no
  runtime or entitlements arguments.
- `Crosswire.app`: ad-hoc signed (the final re-seal step uses `IDENTITY=-`).
- DMG: unsigned.
- Gatekeeper on macOS 15+ Sequoia: first launch is blocked. The user opens
  **System Settings, Privacy and Security, Open Anyway**. The old Control-click to Open bypass
  was removed in Sequoia. First-launch documentation must say this. Because distribution is a
  DMG and not a PKG, this is the only Gatekeeper prompt the user sees.

### Phase 2 (once the Apple Developer Program account is active)

This is **more than a credentials swap**. The following changes are required:

- Add `scripts/engine.entitlements` containing the Wine exception entitlements:
  `com.apple.security.cs.allow-unsigned-executable-memory`,
  `com.apple.security.cs.disable-library-validation`, and
  `com.apple.security.cs.allow-dyld-environment-variables`.
- `sign-engine.sh` is run with `IDENTITY` set to the Developer ID Application identity,
  `RUNTIME="--options runtime --timestamp"`, and `ENTITLEMENTS="scripts/engine.entitlements"`.
  The hardened-runtime flag and timestamp are new; they are not optional for notarization.
- The Xcode project enables hardened runtime (`ENABLE_HARDENED_RUNTIME = YES`) for the release
  configuration, and the release config must not include the `get-task-allow` debug entitlement.
- The outer-app re-seal step uses the Developer ID Application identity plus
  `--options runtime --timestamp` and the app entitlements.
- New pipeline steps: notarize the app (`xcrun notarytool submit --wait`), staple it, build the
  DMG from the stapled app, notarize the DMG, staple the DMG.
- Two certificates are needed only if a PKG is ever reintroduced. With DMG-only distribution,
  only the **Developer ID Application** certificate is required. No Developer ID Installer cert.

Notarization is an automated malware scan, not a human review, and it does not reject the Wine
exception entitlements above. A Developer-ID-signed, notarized Wine app is a proven, supported
configuration.

## Sparkle Update Flow

- The appcast `<enclosure>` points to a `.dmg` containing the new `Crosswire.app`.
- Sparkle replaces the app bundle in place. No admin prompt, because it is an app replacement
  rather than a PKG install. PKG-based Sparkle updates are not used.
- Existing users on the current DMG distribution receive new versions as ordinary Sparkle
  updates; the payload is still an app bundle, so there is no format migration.

### Phase 1 to Phase 2 transition (important)

When the first Developer-ID-signed build ships, existing Phase 1 installs are ad-hoc signed.
Sparkle validates the code-signing continuity of updates, and an ad-hoc to Developer ID
identity change can cause Sparkle to refuse the auto-update for those users. Plan for this:

- Do **not** regenerate the Sparkle EdDSA key between phases. Keep the same `SUPublicEDKey` in
  the app and the same private key in CI secrets, so the EdDSA chain is unbroken.
- Before relying on the auto-update path, explicitly test an ad-hoc build updating to a
  Developer-ID-signed build.
- For the specific transition release, include a direct DMG download link in the release notes
  and an in-app notice, so any user whose auto-update is refused can re-download once.
- Keep Phase 1 public exposure short (treat it as a limited beta) so few users are on ad-hoc
  builds when Phase 2 lands.

## What Users Experience

**Installing for the first time:**
1. Download `Crosswire.dmg`.
2. Open it, drag `Crosswire.app` to the Applications alias.
3. Phase 1 only: first launch is blocked by Gatekeeper; the user opens System Settings,
   Privacy and Security, Open Anyway. One-time, documented prominently.
4. Phase 2: the app opens normally with no friction.

**Getting an update:**
1. Crosswire shows a non-blocking banner: "Crosswire X.Y is available".
2. The user clicks Update.
3. Sparkle downloads the DMG and replaces the app bundle (no admin prompt).
4. The app restarts on the new version.
5. The user has no idea the engine changed; they simply have a newer Crosswire.

**No user ever sees:** Wine, engine, wine64, Crosswire64, Gcenx, or any internal name.

## Out of Scope

- **The Mac App Store.** A general-purpose Wine frontend cannot realistically ship there: the
  App Store requires App Sandbox and does not grant the hardened-runtime exception entitlements
  Wine needs. Developer ID plus notarization is the chosen end state and delivers the full
  trusted experience. The App Store is not a goal.
- Quarantine on `.exe` files dropped into bottles by users. Gatekeeper evaluates these at
  launch; behavior depends on the file's origin and macOS version.
- Building Wine from source. Gcenx is the upstream; their compiled binaries are consumed as a
  dependency. If Gcenx ever disappears, building from source is a future problem.

## Files Affected

| File | Action |
|------|--------|
| `Crosswire/Views/Setup/CrosswireWineDownloadView.swift` | Delete |
| `CrosswireKit/.../CrosswireWine/CrosswireWineInstaller.swift` | Rewrite as `Engine/CrosswireEngine.swift` |
| `CrosswireKit/Sources/CrosswireKit/Wine/Wine.swift` | Update bin path to `Engine/bin/Crosswire64`; rename to `Engine/` |
| `.github/workflows/wine-update-check.yml` | Rename to `engine-update-check.yml`; read `engine-version.txt`, trigger bundle pipeline |
| `.github/workflows/release.yml` | Replace with shared build, sign, DMG, notarize steps; remove PKG and old DMG paths |
| New: `.github/workflows/engine-bundle.yml` | Full bundle pipeline (steps 1 to 17 above) |
| New: `.github/workflows/build-sign-dmg.yml` | Reusable workflow shared by `engine-bundle.yml` and `release.yml` |
| New: `scripts/generate-wrappers.sh` | Generates `Crosswire64`, `Crosswireserver`, `Crosswireboot` with `chmod +x` |
| New: `scripts/sign-engine.sh` | Inside-out Mach-O signing (ad-hoc Phase 1, Developer ID Phase 2) |
| New: `scripts/engine.entitlements` | Wine exception entitlements; used in Phase 2 only |
| New: `engine-version.txt` | Repo-side marker of the currently bundled upstream tag |
| `Crosswire.entitlements` | Confirm Wine entitlements present; align with Phase 2 hardened runtime |
| `CLAUDE.md` | Update engine location, version scheme, wrapper rationale, and signing notes |

## Implementation Order for Claude Code

Work in this sequence. Each numbered group is a coherent, separately committable unit. Commits
are authored as Nicolas Sanchez with no AI attribution anywhere.

1. **App code, no pipeline yet.** Delete the download view and installer download logic. Rename
   the `Wine`-prefixed symbols and the `CrosswireWine` directory to `Engine`. Repoint
   `binFolder` to the in-bundle path. Convert `isEnginePresent()` to an integrity check. Add
   the one-time migration cleanup of the stale Application Support engine. Build and confirm
   the app compiles with the engine path stubbed.
2. **Wrapper generation.** Add `scripts/generate-wrappers.sh`. Verify it produces the three
   executable wrapper scripts and that `Crosswire64` correctly execs `wine64`.
3. **Signing script.** Add `scripts/sign-engine.sh` exactly as specified. Test it locally
   against an extracted Gcenx tree: confirm it signs `.dylib`, `.so`, and Mach-O executables,
   and skips the wrappers and PE `.dll` files. Verify with `codesign --verify`.
4. **Engine versioning.** Add `engine-version.txt` and the build step that generates
   `CrosswireEngineVersion.plist` into the bundle from it.
5. **Reusable build workflow.** Add `.github/workflows/build-sign-dmg.yml` implementing steps
   8 to 15 of the pipeline (build, insert engine, sign engine, re-seal app, DMG, verify; with
   the Phase 2 notarize steps gated behind a flag or secret presence check).
6. **Bundle pipeline.** Add `engine-bundle.yml` implementing steps 1 to 7 and 16 to 17, calling
   the reusable workflow for the middle. Rename `wine-update-check.yml` to
   `engine-update-check.yml` and wire the trigger.
7. **Release workflow.** Update `release.yml` to call the reusable workflow. Remove all PKG and
   legacy DMG logic.
8. **Docs.** Update `CLAUDE.md`.

Phase 2 is a later, separate change set: add `scripts/engine.entitlements`, enable hardened
runtime in the Xcode release config, set the `IDENTITY`, `RUNTIME`, and `ENTITLEMENTS` values
in CI, and turn on the notarize and staple steps. No structural rework of the pipeline is
needed at that point, but it is not a one-line credentials change either.
