# Crosswire — Implementation Plan

**Date:** 2026-05-22
**Repository:** `github.com/grubwire/Crosswire` (public, GPL-3.0), checked out on nick-dev-01 at `D:\Projects`.
**For:** Claude Code.
**Author of record for all commits:** Nicolas Sanchez.

This is the single source of truth. It contains the execution brief, the full Stage 1 plan to
build now, and Stage 2 as a reference appendix. Read the whole document before writing code.

---

# Part 0 — Execution Brief

## What Crosswire is

Crosswire is a macOS app for running Windows software, published by Grubwire. It is a fork of
Whisky (an unmaintained Wine wrapper for macOS) and goes further than Whisky did: its purpose
is to package and deliver the Wine engine so the user never manages it. Whisky never did that;
it is the reason Crosswire exists. The public description is already set and correct: "Run
Windows apps and games on macOS. No scripts, no Terminal, just download and go. Fork of Whisky,
kept current with Gcenx's Wine builds."

The engine is an internal implementation detail. No user-facing text ever names Wine, the
engine, Gcenx, or any internal component. There is only Crosswire.

## The two-stage strategy

Crosswire is built in two stages, sequential, not parallel.

- **Stage 1 — Cloud Download (build now):** a small app. On first run it downloads the engine
  from `data.grubwire.io` and sets up its dependencies. Proven model (Whisky worked this way),
  ships fastest. Full detail in Part 1.
- **Stage 2 — Bundled Engine (do not start):** the engine ships inside the app bundle. Larger
  download, fully offline, no hosting. The long-term destination. Reference detail in Part 2,
  included only so Stage 1 decisions are made with the destination in mind. Do not write Stage
  2 code.

> Naming note: this document uses **Stage 1 / Stage 2** for the two project phases, and
> **signing Phase 1 / Phase 2** for the separate ad-hoc-versus-Developer-ID signing axis. They
> are different things; keep them straight.

Much of Stage 1 is shared work that carries directly into Stage 2 (the renames, the wrapper and
signing scripts, the Rosetta helper, the engine acquisition logic). Building Stage 1 well is
also progress toward Stage 2.

## Licensing — non-negotiable constraints

Crosswire is a fork of Whisky, which is licensed **GPL-3.0**. Crosswire is therefore GPL-3.0 and
stays GPL-3.0. This is settled and is not to be worked around. (The reasons: Whisky had
multiple contributors and no contributor license agreement, so the code cannot be relicensed.
A future closed-source product, if ever wanted, would be a separate clean-room rewrite, not a
conversion of this repo. That is out of scope here.)

Hard rules:
- Keep the `LICENSE` file and all GPL-3.0 terms intact.
- Keep Whisky's original copyright notices in source file headers. Rebranding removes the
  Whisky *brand*, not the *legal attribution*. Brand out, attribution in.
- The repo is public under GPL-3.0. Do not add anything that assumes the source is secret; in
  particular, paid or gated features (if any are added later) must be server-side, never a flag
  in the open-source binary.
- An "Inspired by Whisky" homage line belongs in the About / Acknowledgements screen. Homage,
  not a claim of endorsement or official succession. Acceptable: "Inspired by Whisky", "Fork of
  Whisky, kept current". Not acceptable: "the successor to Whisky", "Whisky 2.0", or any
  wording implying a handoff.
- The Wine engine (via Gcenx) is LGPL-2.1; DXVK is permissively licensed. Both must be credited
  in the Acknowledgements screen with links to their sources.

## Standing repo rules

- All commits authored as **Nicolas Sanchez**.
- No AI attribution anywhere: no Co-Authored-By trailers, no "Generated with" footers, no
  mention of AI in commit messages, PR bodies, READMEs, or workflow output.
- Never use em-dashes in any project text.
- The global gitignore already excludes `CLAUDE.md`, `.claude/`, `AGENTS.md`, `BACKLOG.md`,
  `WORKLOG.md`.

## Work cadence and checkpoints

The repo is already partly renamed toward Crosswire. Do not run all of Stage 1 straight through
unattended. Work to checkpoints and pause for Nick's review at each:

- **Checkpoint A:** after the repo-state inventory (Task 0) — pause before any change.
- **Checkpoint B:** after Task 1, the full scrub — pause; the app must build cleanly first.
- **Checkpoint C:** after the `EngineManifest` model and the signing scripts (Stage 1 steps 3,
  7, 8) — pause; security-critical, needs review.
- **Checkpoint D:** before the R2 bucket and `data.grubwire.io` setup (Stage 1 step 10) —
  pause; needs Nick's accounts and decisions.

Between checkpoints, proceed step by step. Stop immediately and report any problem, ambiguity,
or anything that contradicts this plan.

## Handling naming conflicts during the scrub

The repo is mostly migrated, so the scrub will meet half-renamed states and naming collisions.
Rule: **resolve them using the rename table in Task 1 as the source of truth, and report what
was done at Checkpoint B.** Do not pause on each one. The only exception is genuine ambiguity
the rename table does not cover; pause and ask only then.

## What not to do

- Do not start Stage 2 code.
- Do not start signing Phase 2 work.
- Do not remove or alter the GPL-3.0 license or Whisky's copyright attribution.
- Do not add AI attribution of any kind.
- Do not run unattended past a checkpoint.
- Do not make legal or licensing judgments; they are settled above, follow them.

## Order of work

1. Read this whole document.
2. **Task 0:** repo-state inventory, change nothing. Stop at Checkpoint A.
3. **Task 1:** full brand scrub, build, one commit. Stop at Checkpoint B.
4. Stage 1 steps 2 onward (Part 1), observing Checkpoints C and D.
5. Report problems immediately; never push past a checkpoint without review.

## Task 0 — repo-state inventory (do first, change nothing)

Inventory the repository and report:
- Which symbols, types, files, and directories still carry **Whisky** or **Wine** naming, and
  which are already renamed toward **Crosswire** / **Engine**.
- Current bundle identifier, target names, scheme names.
- The state of the `LICENSE` file and copyright headers.
- Whether `WhiskyKit` has become `CrosswireKit`, fully or partly.

Produce this as a list and stop at Checkpoint A.

## Task 1 — full Whisky-to-Crosswire scrub

After Checkpoint A clears, perform a complete brand scrub. This is Stage 1 step 1 and is
dual-purpose: required now and carries into Stage 2.

Scope, everything:
- **Symbols and types:** every `Whisky`- and `Wine`-prefixed type, function, property to its
  Crosswire / Engine equivalent, per the rename table below. `WhiskyKit` to `CrosswireKit` if not
  already done.
- **Directories and files:** rename `CrosswireWine/` and any `Whisky*` / `Wine*` paths to
  `Engine/`; rename files to match.
- **Identifiers:** bundle identifier, target names, scheme names, org references, any
  `getwhisky` URLs.
- **User-facing strings:** every UI string, menu item, alert, Info.plist value. Nothing the
  user sees names Whisky or Wine.
- **Comments and docs:** code comments, README, other docs.
- **Assets:** the app icon and any Whisky-branded images. Claude Code cannot design an icon;
  produce a list of assets needing replacement and flag it for Nick.

Do NOT touch: the `LICENSE` file, or Whisky's copyright notices in source headers.

Then verify the app builds cleanly. A rename pass that does not compile is not done. Make one
commit only after a clean build. Stop at Checkpoint B.

### Rename table

| Old | New |
|-----|-----|
| `WhiskyKit` | `CrosswireKit` |
| `CrosswireWineInstaller` | `CrosswireEngine` |
| `CrosswireWineVersion` | `CrosswireEngineVersion` |
| `isCrosswireWineInstalled()` | `isEnginePresent()` |
| `CrosswireWineVersion()` | `engineVersion()` |
| `CrosswireKit/.../CrosswireWine/` directory | `CrosswireKit/.../Engine/` |
| any `Wine`-prefixed symbol | `Engine`-prefixed equivalent |
| any user-facing "Whisky" / "Wine" string | Crosswire wording, engine unnamed |

---

# Part 1 — Stage 1: Cloud Download (BUILD THIS)

## Vision

Crosswire is a complete, standalone macOS app for running Windows software. The engine is an
internal implementation detail: not a separate product, not named to the user. The user
installs Crosswire, the app sets itself up once on first launch, and it works.

## Distribution decision

Crosswire ships as a **small DMG** (the app only, no engine, ~10 to 20 MB) for both first
install and app updates. No PKG.

The "double-click, it sets itself up, done" feel comes from the app's own first-run setup
screen ("Setting up Crosswire", with progress), not an installer wizard. A PKG is the wrong
tool: a PKG that downloads the engine in a postinstall script runs as root with no UI and is
fragile; a PKG that just copies the small app equals drag-to-Applications; an unsigned PKG adds
a second Gatekeeper prompt in signing Phase 1. Whisky, the reference for this model, ships as a
DMG and downloads its engine on first launch. Crosswire does the same.

The Mac App Store is out of scope (mandatory App Sandbox, and the hardened-runtime exception
entitlements Wine needs are not granted to App Store apps).

## What we are building

- A small `Crosswire.app` containing no engine, distributed as a DMG.
- An engine archive and a signed manifest hosted on `data.grubwire.io` (Cloudflare R2).
- A first-run setup flow inside the app: check dependencies, fetch manifest, verify, download
  the engine, verify, extract, then proceed.
- An engine update flow: the app checks the manifest and updates the engine independently of
  app updates.
- App updates via Sparkle (DMG), with delta updates enabled.

## Dependencies: Rosetta and the engine

The user authorizes as little as possible and never sees a stack of separate installers.
Crosswire treats Rosetta and the engine as managed dependencies, folded into one "Setting up
Crosswire" flow.

**Rosetta** is an Apple component, not hosted or bundled. On first launch, on Apple Silicon,
the app checks whether Rosetta is present and, if not, installs it with
`softwareupdate --install-rosetta --agree-to-license`. Most Macs already have it, so for most
users this is an instant no-op. When missing, it runs as one quiet step inside the setup flow,
not a separate ceremony. On Intel Macs the check is skipped. This is app launch logic and
carries into Stage 2 unchanged.

**The engine** is the one dependency fetched from the cloud; see below.

## Engine location

The downloaded engine is installed to:

```
~/Library/Application Support/Crosswire/Engine/
  bin/   (Crosswire64 wrappers + wine64 etc.)
  lib/
  share/
~/Library/Application Support/Crosswire/engine-version.json   (installed engine state)
```

Not inside the app bundle. An app that writes into its own `Contents/Resources/` after install
breaks its code signature and, in signing Phase 2, its notarization. Application Support is the
correct location for app-managed downloaded content.

The engine is outside the app bundle, so it is not covered by the app's code signature. That is
expected. Code-signature validity is per-binary: each engine binary is signed individually in
the engine pipeline before upload, so each runs correctly as a subprocess on Apple Silicon.

## Hosting on data.grubwire.io

`data.grubwire.io` is object storage. Use **Cloudflare R2**: zero egress fees, which matters
because every first-run install downloads the full engine (~200 MB). Requirements: public-read
on the engine paths, HTTPS only, the `data.grubwire.io` custom domain bound to the bucket.

One bucket holds two tiers, `test` and `prod`, as separate prefixes (see Build Pipeline for the
full dev-to-test-to-prod story). Each tier has its own manifest:

```
https://data.grubwire.io/engine/
  test/
    engine-manifest.json
    engine-manifest.json.sig
    archives/Crosswire-engine-11.9.tar.xz
  prod/
    engine-manifest.json
    engine-manifest.json.sig
    archives/
      Crosswire-engine-11.9.tar.xz
      Crosswire-engine-11.8.tar.xz    <- keep prior versions for rollback
```

`engine-manifest.json` (the `url` points within whichever tier the manifest belongs to):

```json
{
  "schemaVersion": 1,
  "engineVersion": "1.1.9",
  "upstreamTag": "11.9",
  "url": "https://data.grubwire.io/engine/prod/archives/Crosswire-engine-11.9.tar.xz",
  "sha256": "<hex digest of the tar.xz>",
  "sizeBytes": 209715200,
  "minAppVersion": "1.0.0"
}
```

`engine-manifest.json.sig` is a detached Ed25519 signature over the exact bytes of the manifest.

Which tier the app reads is a build setting, not a runtime choice. A test build has the `test`
manifest URL compiled in; a release build has the `prod` URL. Shipped users read only `prod`.

## Engine integrity (mandatory from the first release)

Stage 1 downloads and then executes code fetched over the network. Verification ships with the
first build; it is not deferred.

1. **Signed manifest.** A SHA-256 alone is not enough: an attacker who can modify the bucket
   can change the archive and the listed hash together. The manifest is signed with an Ed25519
   private key held only in CI secrets; the app embeds the public key and verifies the
   signature before trusting anything in the manifest. This is a dedicated key, separate from
   the Sparkle EdDSA key. The app verifies with CryptoKit (`Curve25519.Signing`); CI signs with
   an Ed25519 key.
2. **Archive checksum.** After download, the app computes the archive SHA-256 and compares it
   to the verified manifest. A mismatch aborts the install with a clear error and no extraction.

Only after both checks pass is the archive extracted.

**Quarantine:** files written by the app via `URLSession` are not normally given the
`com.apple.quarantine` attribute, so the extracted engine usually has none. As a defensive
measure the app still clears quarantine recursively on the extracted tree
(`xattr -dr com.apple.quarantine`) after extraction.

## Wrapper scripts (shared with Stage 2)

Gcenx binaries cannot be renamed without recompiling Wine from source; they reference each
other internally by name. Wrapper scripts provide Crosswire-named entry points:

```sh
#!/bin/sh
exec "$(dirname "$0")/wine64" "$@"
```

`Crosswire64`, `Crosswireserver`, `Crosswireboot` are thin wrappers of this form. All Swift code
calls `Crosswire64` only, by absolute path resolved from the engine location; `wine64` is never
referenced in app code. The wrappers have no extension and cannot be Mach-O signed; the signing
script detects this by content. Generated by `scripts/generate-wrappers.sh`.

## Signing the engine binaries (shared script with Stage 2)

`codesign --force --deep` is never used: `--deep` is deprecated and unreliable for nested
binaries. On Apple Silicon every Mach-O image needs a valid signature (ad-hoc is enough in
signing Phase 1) or it is killed on launch or load.

`scripts/sign-engine.sh` signs every Mach-O file anywhere under the engine, detected with
`file`, including the `.so` Wine builtins under `lib/wine/` (not just `.dylib`) and Mach-O
executables. It skips non-Mach-O files (wrapper scripts, PE `.dll` files, data). In Stage 1
this runs in the engine pipeline against the extracted tree, before the archive is packaged.

```bash
#!/bin/bash
# Signs every Mach-O file under the engine, inside-out.
# Signing Phase 1 (ad-hoc):       IDENTITY=-
# Signing Phase 2 (Developer ID): IDENTITY="Developer ID Application: NAME (TEAMID)"
#                                 RUNTIME="--options runtime --timestamp"
#                                 ENTITLEMENTS="scripts/engine.entitlements"
set -euo pipefail

ENGINE="$1"
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
    codesign --force --sign "$IDENTITY" "${runtime_args[@]}" "${ent_args[@]}" "$f"
  elif [[ "$desc" == *Mach-O* ]]; then
    codesign --force --sign "$IDENTITY" "${runtime_args[@]}" "$f"
  fi
done < <(find "$ENGINE" -type f)
```

The engine archive itself does not need notarization: the engine binaries are launched as
subprocesses, and subprocess execution checks code-signature validity, not Gatekeeper
notarization. Valid signatures plus cleared quarantine are sufficient.

## First-run setup flow

On launch the app checks for a usable engine in Application Support. If absent or incomplete,
it shows the setup screen and runs, as one continuous flow:

1. On Apple Silicon, check for Rosetta; if missing, install it. No-op for most users.
2. Fetch `engine-manifest.json` and `engine-manifest.json.sig` from `data.grubwire.io`.
3. Verify the signature with the embedded Ed25519 public key. On failure, abort with a clear
   error and do not proceed.
4. Check `minAppVersion` against the running app; if too old, tell the user to update the app
   first.
5. Download the archive named in the manifest, showing real progress.
6. Compute the archive SHA-256 and compare it to the manifest. On mismatch, abort and delete
   the partial download.
7. Extract to a temporary directory, then move it into the engine location atomically (extract
   beside the target, then rename), so a crash mid-extract never leaves a half-written engine.
8. Clear quarantine recursively on the extracted tree.
9. Write `engine-version.json` recording the installed engine version and upstream tag.
10. Proceed to the normal app UI.

If a usable engine is already present, setup is skipped and the app opens directly.

## Engine update flow

The app checks the manifest on a throttled cadence (once per launch, throttled, or a daily
timer). If the manifest engine version is newer than the installed `engine-version.json`, the
app downloads and verifies the new archive in the background and installs it the same way
(atomic extract-then-rename), swapping on next launch or immediately if no engine process is
running. This is independent of Sparkle. A release build reads the `prod` manifest; prior prod
archives are retained so a bad version can be rolled back by reverting the prod manifest.

## Failure handling

Stage 1 requires network access on first run. The setup flow must handle this well:
- No network or failed download: a clear, non-technical error with a Retry action. Never a
  blank or indefinitely spinning screen.
- Verification failure (bad signature or hash mismatch): abort, delete the partial download,
  show an error that does not invite bypassing the check.
- Interrupted extraction: extraction is to a temp directory followed by an atomic rename, so an
  interruption leaves the previous state intact and the next launch retries cleanly.
- Out of disk space: detect before extracting using the manifest `sizeBytes`, and report it.

## Build pipeline

Stage 1 has two artifacts, built and released independently.

### Engine archive: dev to test to prod

The engine moves through three tiers so a broken upstream build or a pipeline bug is caught
before it reaches a shipped user. Promotion between tiers is always deliberate, never automatic.

**Dev (GitHub Actions, no R2).** `engine-bundle.yml` is triggered weekly by
`engine-update-check.yml` when the latest Gcenx tag differs from the current prod manifest
version. It runs entirely on the runner:

1. Query the latest Gcenx release via the GitHub API; select the asset by priority (table below).
2. Download and extract the `.tar.xz`; rename the top-level directory to `Engine/`.
3. Generate wrapper scripts via `scripts/generate-wrappers.sh`.
4. Run `scripts/sign-engine.sh` against the extracted tree (ad-hoc in signing Phase 1).
5. Repackage the signed tree as `Crosswire-engine-X.Y.tar.xz`; compute SHA-256 and size.
6. Boot smoke test: initialize a throwaway prefix with `Crosswireboot` and confirm `wine64` runs
   and reports a version. If this fails, stop, produce no artifact, open a GitHub issue.
7. If the smoke test passes, generate `engine-manifest.json`, sign it with
   `scripts/sign-manifest.sh`, and upload both as a GitHub Actions artifact (or attach to a
   draft release). Nothing has touched R2. No app can reach this build yet.
8. Open a GitHub issue noting a new engine build passed dev and is ready to promote to test.

**Test (R2 `engine/test/`).** A separate workflow, `engine-promote-test.yml`, triggered
manually. It takes the artifact from a passing dev run, uploads the archive to
`engine/test/archives/`, and uploads the test `engine-manifest.json` and `.sig` last (so the
manifest never points at an object not yet present). A test build of Crosswire, which has the
test manifest URL compiled in, now pulls this engine. Nick installs that build and exercises it
(runs a real game) before going further.

**Prod (R2 `engine/prod/`).** A second workflow, `engine-promote-prod.yml`, triggered manually
or by a release tag. It copies the exact archive already validated in test from
`engine/test/archives/` to `engine/prod/archives/`, then writes the prod `engine-manifest.json`
and `.sig` last. Shipped users read only `prod`. Every prior prod archive is retained, so
rollback is reverting the prod manifest to the previous version's entry, a one-file change.

### App DMG (`release.yml`)

Builds the small `Crosswire.app` (no engine), signs it (ad-hoc in signing Phase 1), builds the
DMG, generates the Sparkle delta against the previous version, and in signing Phase 2 notarizes
and staples. A normal small-app release that does not touch the engine pipeline.

### Upstream asset priority

| Priority | Asset name |
|----------|-----------|
| 1 | `wine-stable-*` (if Gcenx restores it) |
| 2 | `wine-staging-*` |
| 3 | `wine-devel-*` |
| 4 | any `.tar.xz` |

## Version mapping

The engine version is decoupled from the app version. The engine version lives in the manifest
(`engineVersion`, `upstreamTag`) and the installed `engine-version.json`. The app version is
independent and managed by normal app releases.

## A note on update cost

Bundling the engine (Stage 2) does not force a ~200 MB re-download on every update, and this
should not drive the Stage 1 versus Stage 2 thinking. The engine is a resource, not compiled
code, so updating it never recompiles the app; and Sparkle delta updates ship only the changed
bytes. Ongoing update downloads are small in both stages. The real difference is: Stage 1 has a
smaller first download and needs network on first run; Stage 2 has no hosting, no server attack
surface, fewest authorizations, and works offline.

## Code changes in Crosswire

### Kept and rewritten

- `CrosswireWineDownloadView.swift` is kept, renamed `EngineSetupView.swift`, rewritten to drive
  the first-run setup flow, fetch from the `data.grubwire.io` manifest instead of the Gcenx
  GitHub API, run the Rosetta check, and verify signature and hash.
- `CrosswireWineInstaller` download and install logic is kept, renamed `CrosswireEngine`,
  rewritten to target Application Support, the signed manifest, and the integrity checks.

### Renamed

Per the rename table in Part 0.

### Updated

- `CrosswireEngine.binFolder` resolves to the engine path under Application Support.
- All process launches reference `Crosswire64` by absolute path, never `wine64`.
- No user-facing strings name Wine or Gcenx. "Setting up Crosswire" is acceptable setup language.
- `isEnginePresent()` checks for a complete, usable engine and drives whether setup runs.

### New

- A `RosettaCheck` helper (Apple Silicon detection, presence check, install invocation).
- An `EngineManifest` model with Ed25519 signature verification and SHA-256 archive verification.
- `engine-version.json` read and write in Application Support.
- The embedded Ed25519 public key for manifest verification.
- An About / Acknowledgements screen crediting Wine, Gcenx, DXVK, and Whisky, with source
  links, including the "Inspired by Whisky" homage line.

### Kept unchanged

- Bottle management, program launching, DXVK, winetricks, Rosetta2 utilities, PE parsing, and
  all UI views other than the setup flow.

## Signing roadmap

### Signing Phase 1 (no Developer ID yet)

- Engine binaries: ad-hoc signed in the engine pipeline before upload.
- `Crosswire.app`: ad-hoc signed. DMG: unsigned.
- Manifest signing (Ed25519): active from the first release; unrelated to code signing.
- Gatekeeper on macOS 15+ Sequoia: one "Open Anyway" step on first app launch (the
  Control-click bypass was removed in Sequoia).

### Signing Phase 2 (Apple Developer Program account active)

This is more than a credentials swap:
- Add `scripts/engine.entitlements` with the Wine exception entitlements:
  `com.apple.security.cs.allow-unsigned-executable-memory`,
  `com.apple.security.cs.disable-library-validation`,
  `com.apple.security.cs.allow-dyld-environment-variables`.
- Run `sign-engine.sh` with the Developer ID Application identity,
  `RUNTIME="--options runtime --timestamp"`, and the entitlements file.
- Enable hardened runtime in the Xcode release config; ensure no `get-task-allow` entitlement.
- `Crosswire.app`: Developer ID Application, hardened runtime, notarized, stapled. DMG:
  notarized and stapled.
- Only the Developer ID Application certificate is needed (DMG-only, no Installer cert).

Notarization is an automated malware scan; it does not reject the Wine entitlements above.
Do not start signing Phase 2 now.

## Sparkle update flow

Sparkle updates the app only: the appcast points to a small DMG, Sparkle swaps the app bundle,
no admin prompt. Enable delta updates. The engine is not part of Sparkle in Stage 1; it is
handled by the manifest-driven engine update flow.

Keep the Sparkle EdDSA key stable across signing phases. The ad-hoc to Developer ID transition
can make Sparkle refuse the auto-update for existing ad-hoc installs; test that transition and
ship the first Developer ID build with a direct download link in the release notes.

## What users experience

**First install:** download the small `Crosswire.dmg`, drag the app to Applications. Signing
Phase 1 only: one Gatekeeper "Open Anyway" step. The app then shows "Setting up Crosswire" with
progress while it checks Rosetta and downloads and verifies the engine, once. Then it opens.

**Updating:** the app updates via Sparkle (small delta downloads); the engine updates quietly
in the background when a new version is published. The user never sees Wine or Gcenx named.

## Files affected

| File | Action |
|------|--------|
| `Crosswire/Views/Setup/CrosswireWineDownloadView.swift` | Rename to `EngineSetupView.swift`, rewrite |
| `CrosswireKit/.../CrosswireWine/CrosswireWineInstaller.swift` | Rewrite as `Engine/CrosswireEngine.swift` |
| `CrosswireKit/Sources/CrosswireKit/Wine/Wine.swift` | Update bin path to the Application Support engine; move to `Engine/` |
| `.github/workflows/wine-update-check.yml` | Rename to `engine-update-check.yml`; compare the latest Gcenx tag against the prod manifest version |
| `.github/workflows/release.yml` | Build and release the small app DMG; generate Sparkle deltas |
| New: `.github/workflows/engine-bundle.yml` | Dev tier: build, sign, package, smoke test, produce a GitHub artifact |
| New: `.github/workflows/engine-promote-test.yml` | Promote a passing dev artifact to R2 `engine/test/` |
| New: `.github/workflows/engine-promote-prod.yml` | Promote the validated test archive to R2 `engine/prod/` |
| New: `scripts/generate-wrappers.sh` | Generates the three wrapper scripts |
| New: `scripts/sign-engine.sh` | Inside-out Mach-O signing |
| New: `scripts/sign-manifest.sh` | Ed25519 signing of `engine-manifest.json` |
| New: `scripts/engine.entitlements` | Wine exception entitlements (signing Phase 2) |
| New: `CrosswireKit/.../Engine/EngineManifest.swift` | Manifest model, signature and hash verification |
| New: `CrosswireKit/.../Engine/RosettaCheck.swift` | Rosetta detection and install |
| `Crosswire` About/Acknowledgements view | Add credits for Wine, Gcenx, DXVK, Whisky, with source links and the homage line |
| `CLAUDE.md` | Document the two-stage strategy, the manifest format, the dev/test/prod flow, licensing |

## Stage 1 implementation order

1. Task 0 inventory, then Task 1 scrub (Part 0). Checkpoints A and B.
2. Add the `RosettaCheck` helper (shared with Stage 2).
3. Define the manifest format; add the `EngineManifest` model with Ed25519 signature
   verification and SHA-256 archive verification. Generate the Ed25519 key pair; the private
   key goes into CI secrets, the public key is embedded in the app. The test and prod manifest
   URLs are a build setting. (Checkpoint C is after step 4 below.)
4. Rewrite `CrosswireEngine` to download from the manifest, verify, and install to Application
   Support with atomic extract-then-rename and quarantine clearing. Add
   `scripts/generate-wrappers.sh` and `scripts/sign-engine.sh`. **Stop at Checkpoint C.**
5. Rewrite the setup view as `EngineSetupView`, including the Rosetta step and the failure and
   retry handling.
6. Add the engine update flow (manifest check, background update).
7. Add `scripts/sign-manifest.sh` and the `engine-bundle.yml` dev pipeline (build, sign,
   package, smoke test, artifact). Add `engine-promote-test.yml` and `engine-promote-prod.yml`.
8. Update `release.yml` for the small app DMG with Sparkle deltas; rename and wire
   `engine-update-check.yml`.
9. **Stop at Checkpoint D.** Set up the R2 bucket with `engine/test/` and `engine/prod/`
   prefixes and the `data.grubwire.io` custom domain; manual end-to-end test of the first-run
   flow against real hosting.
10. Add the About / Acknowledgements screen with the required license credits.
11. Update `CLAUDE.md`.

Signing Phase 2 is a later, separate change set; do not start it.

---

# Part 2 — Stage 2: Bundled Engine (REFERENCE ONLY, DO NOT BUILD)

Stage 2 is the long-term destination. It is included so Stage 1 is built with the destination
in mind. **Do not write Stage 2 code as part of this work.**

## Summary

In Stage 2 the engine ships pre-extracted inside the app bundle, signed at build time, and the
app is distributed as a DMG containing the full `Crosswire.app`. There is no download on first
run, no hosting, no manifest. The app works fully offline and authorizes once.

## Key differences from Stage 1

- The engine lives at `Crosswire.app/Contents/Resources/Engine/`, inserted into the bundle
  **after `xcodebuild` builds the app** and **before the bundle is re-sealed**. It is never
  extracted at install time (that would break the signature and notarization).
- The setup/download view (`EngineSetupView`) is deleted. The manifest model, signature and
  hash verification, the engine update flow, and the embedded Ed25519 key are removed. R2 is no
  longer used by the app.
- `CrosswireEngine.binFolder` resolves to the in-bundle engine path instead of Application
  Support.
- `isEnginePresent()` becomes an integrity check (a bundled engine should always be present; if
  not, the install is corrupt and the app shows a reinstall prompt).
- A one-time first-launch cleanup deletes any engine left in Application Support by a Stage 1
  build. It must not delete bottles or wineprefixes.
- The pipeline changes from "upload an archive to R2" to "insert the engine into the app
  bundle, sign, re-seal, DMG". A committed `engine-version.txt` marker replaces the manifest as
  the CI comparison source.

## Carried over unchanged from Stage 1

The Wine-to-Engine renames, the `RosettaCheck` helper (now a fast pre-flight check rather than
part of a download flow), `scripts/generate-wrappers.sh`, `scripts/sign-engine.sh`,
`scripts/engine.entitlements`, the decoupled version mapping, and the Gcenx upstream check and
asset priority logic.

## Update cost

Bundling does not make updates expensive: the engine is a resource not code, and Sparkle delta
updates ship only changed bytes. The ~200 MB is a one-time first-install cost.

## Why Stage 2 is the destination

No hosting, no server attack surface, no network dependency on first run, fewest
authorizations, works offline. Stage 1 ships sooner; Stage 2 is the cleaner end state. Moving
from Stage 1 to Stage 2 is a real, separate piece of work, scoped above, not a switch.