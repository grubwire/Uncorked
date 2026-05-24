# Crosswire Engine Integration — Design Spec

**Date:** 2026-05-23
**Status:** Approved (revised after design review)

## Vision

Crosswire is a complete, standalone macOS app for running Windows software. The engine is an
internal implementation detail — not a user-facing concept, not a download, not a separate
product. Users install Crosswire, it works. That is the entire experience.

There is no "Wine" in Crosswire. There is no "engine" visible to users. There is only Crosswire.

## What We Are Building

A PKG installer for first install, with Sparkle DMG-based updates thereafter:
- The engine ships pre-extracted inside the app bundle, signed at build time
- PKG installs the whole pre-signed app to /Applications — no postinstall extraction
- App opens cold, engine is already there, nothing to download
- Updates arrive as new Crosswire versions via Sparkle (DMG, not PKG)
- New upstream engine builds are detected automatically and queued as draft releases

## Distribution Format

**First install: PKG installer**
- PKG payload is the fully pre-extracted, pre-signed `Crosswire.app`
- The PKG copies it to `/Applications` — that is all it does
- No postinstall extraction into the bundle (which would invalidate the signature)
- No xattr quarantine strip in postinstall — PKG installers do not propagate quarantine
  from the downloaded PKG to the installed payload; the strip is unnecessary and wrong
- Download size ~200MB (engine compressed within PKG payload), installed size ~600MB

**Subsequent updates: Sparkle DMG**
- appcast `<enclosure>` points to a `.dmg` containing the new `Crosswire.app`
- Sparkle replaces the app bundle without requiring an admin prompt
- PKG format is not used for Sparkle updates — shelling out to `installer` triggers an
  admin authorization prompt and is not silent; DMG-based app replacement avoids this
- Existing users on the current DMG distribution receive this as a normal Sparkle update;
  no migration step needed because the update payload is still an app bundle

## Engine Location Inside the App

The engine is placed inside the app bundle **at build time**, not at install time.

```
Crosswire.app/
  Contents/
    Resources/
      Engine/
        bin/
          Crosswire64       ← wrapper script → wine64
          Crosswireserver   ← wrapper script → wineserver
          Crosswireboot     ← wrapper script → wineboot
          wine64           ← Gcenx binary (internal only)
          wineserver       ← Gcenx binary (internal only)
          wineboot         ← Gcenx binary (internal only)
          [other binaries]
        lib/
        share/
```

Because the engine is placed and signed before the app bundle is sealed, Phase 2 signing
(Developer ID + notarization) works without architectural changes. The only change in Phase 2
is swapping ad-hoc signatures for Developer ID signatures in CI.

### Wrapper Scripts

Gcenx binaries cannot be renamed without recompiling from source — they reference each other
by name internally. Wrapper scripts provide Crosswire-named entry points:

```sh
#!/bin/sh
exec "$(dirname "$0")/wine64" "$@"
```

`Crosswire64`, `Crosswireserver`, `Crosswireboot` are thin wrappers of this form. All Swift code
in CrosswireKit calls `Crosswire64` only — `wine64` is never referenced in app code.

Wrapper scripts cannot be code-signed as Mach-O. This is fine for Phase 1. For Phase 2,
confirm that the existing entitlement `com.apple.security.cs.allow-unsigned-executable-memory`
(already present in `Crosswire.entitlements`) plus disabled library validation covers the
engine's dynamic loading behavior. Wine's loader is known to need this entitlement.

## Signing — Correct Procedure

`codesign --force --deep` must NOT be used. `--deep` is deprecated, unreliable for nested
binaries, and does not sign independent executables in a flat directory correctly. On Apple
Silicon, every executable must have a valid signature (ad-hoc is sufficient in Phase 1) or
it will be killed on launch.

**Correct signing order — inside-out:**

1. Sign all `.dylib` files individually
2. Sign all helper executables individually
3. Sign framework bundles (if any) inside-out
4. Sign the wrapper scripts (skip — shell scripts cannot be Mach-O signed)
5. Sign the outer `Crosswire.app` bundle last

```bash
# Example CI signing step (Phase 1 — ad-hoc)
ENGINE="$APP/Contents/Resources/Engine"

# Sign dylibs first
find "$ENGINE" -name "*.dylib" | while read f; do
  codesign --force --sign - "$f"
done

# Sign executables (skip shell scripts)
find "$ENGINE/bin" -type f ! -name "*.sh" | while read f; do
  file "$f" | grep -q Mach-O && codesign --force --sign - "$f"
done

# Sign the app bundle last
codesign --force --sign - "$APP"
```

In Phase 2, replace `-` with the Developer ID Application identity. Structure is identical.

## Build Pipeline

### Trigger

`engine-update-check.yml` (renamed from `wine-update-check.yml`) runs weekly on macOS.
When a new Gcenx release tag differs from the version currently committed in the repo,
it triggers `engine-bundle.yml` automatically.

### Bundle Pipeline Steps

1. Fetch the latest Gcenx release via GitHub API
2. Download preferred asset (`wine-staging-*` → `wine-devel-*` → any `.tar.xz`)
3. Extract the tarball
4. Rename the top-level directory to `Engine/`
5. Generate wrapper scripts (`Crosswire64`, `Crosswireserver`, `Crosswireboot`) with `chmod +x`
6. Sign all binaries individually, inside-out (see Signing section)
7. Place the signed `Engine/` into the app bundle at `Crosswire.app/Contents/Resources/Engine/`
8. Bump Crosswire version (see Version Mapping below)
9. Build `Crosswire.app` via `xcodebuild`
10. Sign the outer app bundle
11. Build the PKG: `pkgbuild` (app → /Applications) + `productbuild` (no postinstall script needed)
12. Build the Sparkle DMG (containing the new `Crosswire.app`)
13. Create a **draft** GitHub release with both PKG and DMG attached
14. Open a GitHub issue that the draft is ready for testing

You test both artifacts, then publish. Sparkle's appcast is updated to point to the DMG.
Existing users get the DMG update; new users download the PKG.

### Upstream Asset Priority

| Priority | Asset name |
|----------|-----------|
| 1 | `wine-stable-*` (if Gcenx restores it) |
| 2 | `wine-staging-*` |
| 3 | `wine-devel-*` |
| 4 | any `.tar.xz` |

## Version Mapping

Crosswire's version is **fully decoupled** from the engine version. The engine version never
appears in Crosswire's version string — doing so would leak internal implementation details
and break the "users never know what changed" goal.

Simple rule:
- Engine-only updates increment Crosswire's **patch** version (1.0.2 → 1.0.3)
- App feature/fix releases also increment patch or minor as appropriate
- The engine version is recorded in an internal plist (not user-visible) for diagnostics

The internal plist (`CrosswireEngineVersion.plist` in Application Support) stores the
upstream tag (e.g., `11.9`) for use in bug reports and support tooling only.

## Code Changes in Crosswire

### Deleted

- `Crosswire/Views/Setup/CrosswireWineDownloadView.swift` — runtime download screen
- All Gcenx GitHub API calls from within the running app
- The setup/onboarding flow that gates the app behind an engine download
- `CrosswireWineInstaller` install/download logic (engine is pre-bundled; installer gone)

### Renamed

Every `Wine`-prefixed symbol becomes the Crosswire equivalent:

| Old | New |
|-----|-----|
| `CrosswireWineInstaller` | `CrosswireEngine` |
| `CrosswireWineVersion` | `CrosswireEngineVersion` |
| `isCrosswireWineInstalled()` | `isEnginePresent()` |
| `CrosswireWineVersion()` | `engineVersion()` |
| `binFolder` path | `Bundle.main.resourceURL/Engine/bin` |
| `CrosswireKit/.../CrosswireWine/` directory | `CrosswireKit/.../Engine/` |

### Updated

- `CrosswireEngine.binFolder` resolves to `Crosswire.app/Contents/Resources/Engine/bin`
- All process launches reference `Crosswire64`, never `wine64`
- No user-facing strings mention Wine, engine, or internal version numbers
- `UncorkError` and related error types reviewed for any Wine naming

### Kept

- All bottle management (Bottle, BottleSettings, BottleData)
- All program launching logic (Program, ProgramSettings)
- DXVK, winetricks, Rosetta2 utilities
- PE binary parsing
- All existing UI views except the setup/download flow

## Signing Roadmap

### Phase 1 (no Developer ID yet)

- Engine binaries: ad-hoc signed individually, inside-out, in CI pipeline
- `Crosswire.app`: ad-hoc signed
- PKG: unsigned
- Gatekeeper behavior on macOS 15+ Sequoia: the first launch is blocked; users must go to
  **System Settings → Privacy & Security → Open Anyway**. The old right-click → Open bypass
  was removed in Sequoia. First-launch instructions in documentation must reflect this.

### Phase 2 (once Apple Developer account is active)

- Engine binaries: signed with Developer ID Application in CI (same inside-out script,
  swap `-` for the identity)
- `Crosswire.app`: signed with Developer ID Application + hardened runtime + notarized
- PKG: signed with Developer ID Installer + notarized
- Gatekeeper passes cleanly, no user workarounds, no Privacy & Security step
- No structural changes to the pipeline — credentials only

## What Users Experience

**Installing for the first time:**
1. Download `Crosswire.pkg` (~200MB)
2. Double-click, click through standard macOS install screens
3. Crosswire appears in /Applications, fully ready
4. **Phase 1 only:** first launch is blocked by Gatekeeper; user goes to System Settings →
   Privacy & Security → Open Anyway. This is a one-time step, documented prominently.
5. **Phase 2:** no friction — app opens normally

**Getting an update:**
1. Crosswire shows a non-blocking banner: "Crosswire X.Y is available"
2. User clicks Update
3. Sparkle downloads the DMG and replaces the app bundle (no admin prompt)
4. App restarts on the new version
5. User has no idea the engine changed — they just have a newer Crosswire

**No user ever sees:** Wine, engine, wine64, Crosswire64, Gcenx, or any internal name.

## Out of Scope

- Quarantine on `.exe` files dropped into bottles by users. Gatekeeper evaluates these
  at launch; behavior depends on the file's origin and macOS version. Not addressed here.
- Building Wine from source. Gcenx is the upstream; their compiled binaries are consumed
  as a dependency. If Gcenx ever disappears, building from source is a future problem.

## Files Affected

| File | Action |
|------|--------|
| `Crosswire/Views/Setup/CrosswireWineDownloadView.swift` | Delete |
| `CrosswireKit/.../CrosswireWine/CrosswireWineInstaller.swift` | Rewrite as `Engine/CrosswireEngine.swift` |
| `CrosswireKit/Sources/CrosswireKit/Wine/Wine.swift` | Update bin path to `Engine/bin/Crosswire64` |
| `.github/workflows/wine-update-check.yml` | Rename → `engine-update-check.yml`, trigger bundle pipeline |
| `.github/workflows/release.yml` | Add PKG + Sparkle DMG build, keep existing flow as fallback |
| New: `.github/workflows/engine-bundle.yml` | Full bundle pipeline (steps 1-14 above) |
| New: `scripts/generate-wrappers.sh` | Generates `Crosswire64` etc. wrapper scripts with correct permissions |
| New: `scripts/sign-engine.sh` | Inside-out signing script (ad-hoc Phase 1, Developer ID Phase 2) |
| `CLAUDE.md` | Update engine location, version scheme, wrapper script rationale |
