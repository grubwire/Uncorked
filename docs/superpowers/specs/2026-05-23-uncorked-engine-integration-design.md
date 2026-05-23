# Uncorked Engine Integration — Design Spec

**Date:** 2026-05-23
**Status:** Approved

## Vision

Uncorked is a complete, standalone macOS app for running Windows software. The Wine runtime
is an internal engine — not a user-facing concept, not a download, not a separate product.
Users install Uncorked, it works. That is the entire experience.

There is no "Wine" in Uncorked. There is no "engine" visible to users. There is only Uncorked.

## What We Are Building

A PKG installer distribution where:
- The Uncorked engine (built from Gcenx's upstream Wine binaries) ships bundled inside the app
- Installation is: double-click PKG, click through standard install screens, done
- The app opens cold, the engine is already there, nothing to download or set up
- Updates arrive as new Uncorked versions via Sparkle — users never know what changed internally
- New upstream engine builds are detected automatically, bundled, and queued as draft releases

## Distribution Format

**PKG installer** (replacing the current DMG).

- Download size: ~200MB (engine compressed inside the PKG)
- Installed size: ~600MB
- The PKG post-install script extracts the engine to `Uncorked.app/Contents/Resources/Engine/`
- The PKG post-install script runs `xattr -drs com.apple.quarantine /Applications/Uncorked.app`
  so users never need to do this manually (Phase 1 stopgap until Developer ID signing)
- After install, app opens immediately with no first-launch setup

## Engine Location Inside the App

```
Uncorked.app/
  Contents/
    Resources/
      Engine/
        bin/
          uncorked64       ← wrapper script → wine64
          uncorkedserver   ← wrapper script → wineserver
          uncorkedboot     ← wrapper script → wineboot
          wine64           ← Gcenx compiled binary (internal, not exposed)
          wineserver        ← Gcenx compiled binary (internal, not exposed)
          wineboot          ← Gcenx compiled binary (internal, not exposed)
          [other wine bins]
        lib/
        share/
```

### Wrapper Scripts

Since Gcenx binaries are pre-compiled, their internal names cannot be changed without
recompiling Wine from source. Wrapper scripts provide Uncorked-named entry points:

```sh
#!/bin/sh
exec "$(dirname "$0")/wine64" "$@"
```

`uncorked64`, `uncorkedserver`, `uncorkedboot` are all thin wrappers of this form. All
Swift code in UncorkedKit references `uncorked64` only — never `wine64` directly.

## Code Changes in Uncorked

### Deleted

- `Uncorked/Views/Setup/UncorkedWineDownloadView.swift` — entire runtime download screen
- All Gcenx GitHub API calls from within the app
- The setup/onboarding flow that gates the app behind an engine download
- All install/version management that lived in `UncorkedWineInstaller`

### Renamed

Every `Wine`-prefixed symbol becomes an `Uncorked`-prefixed equivalent:

| Old | New |
|-----|-----|
| `UncorkedWineInstaller` | `UncorkedEngine` |
| `UncorkedWineVersion` | `UncorkedEngineVersion` |
| `UncorkedWineDownloadView` | deleted |
| `isUncorkedWineInstalled()` | `isEngineInstalled()` |
| `uncorkedWineVersion()` | `engineVersion()` |
| `binFolder` path | points to `Bundle.main.resourceURL/Engine/bin` |

### Updated

- `UncorkedEngine.binFolder` resolves to `Uncorked.app/Contents/Resources/Engine/bin`
- All Wine process launches call `uncorked64` not `wine64`
- No user-facing strings mention Wine, engine, or any version number other than Uncorked's own
- `UncorkError` enum and any Wine-specific error types reviewed for naming

### Kept

- All bottle management (Bottle, BottleSettings, BottleData)
- All program launching logic (Program, ProgramSettings)
- DXVK, winetricks, Rosetta2 utilities
- PE binary parsing
- All existing UI views except the setup/download flow

## Build Pipeline

### Trigger

The existing `wine-update-check.yml` (renamed to `engine-update-check.yml`) runs weekly.
When a new Gcenx release is detected and differs from the currently bundled version, it
triggers the bundle pipeline automatically.

### Bundle Pipeline Steps

1. Download the upstream tar.xz from Gcenx (`wine-staging-X.Y-osx64.tar.xz` preferred,
   fall back to `wine-devel-X.Y-osx64.tar.xz`)
2. Extract the tarball
3. Rename the top-level directory to `Engine/`
4. Generate wrapper scripts (`uncorked64`, `uncorkedserver`, `uncorkedboot`) in `Engine/bin/`
5. Ad-hoc re-sign all binaries: `codesign --force --deep -s -` (Phase 1 only)
6. Compress `Engine/` back to a tar.xz for bundling in the PKG
7. Bump Uncorked version (minor version for engine updates, e.g., 1.0.2 → 1.1.0)
8. Commit the new engine archive and version bump to a release branch
9. Build `Uncorked.app` via `xcodebuild`
10. Run `pkgbuild` + `productbuild` to produce `Uncorked-X.Y.pkg`
11. Create a **draft** GitHub release with the PKG attached
12. Notify (GitHub issue or Slack) that a draft release is ready for review

You test the draft, then publish. Sparkle picks up the new version and notifies users.

### Upstream Source Priority

| Priority | Asset name |
|----------|-----------|
| 1 | `wine-stable-*` (if Gcenx ever restores it) |
| 2 | `wine-staging-*` |
| 3 | `wine-devel-*` |
| 4 | any `.tar.xz` |

### Naming Convention

Gcenx uses tag format `X.Y` (e.g., `11.9`). Uncorked version maps as:
- Engine `11.9` → Uncorked `1.1.9` (or similar agreed scheme)
- The exact mapping scheme is decided before Phase 1 ships and documented in CLAUDE.md

## PKG Construction

```
productbuild
  └── pkgbuild (Uncorked.app → /Applications)
      └── scripts/
            postinstall   ← extracts Engine/, runs xattr strip
```

Tools: `pkgbuild`, `productbuild` (available on all macOS GitHub Actions runners).
The PKG itself is ad-hoc signed in Phase 1. In Phase 2, it is signed with Developer ID Installer.

## Signing Roadmap

### Phase 1 (Current — no Developer ID)

- Engine binaries: ad-hoc signed (`codesign --force --deep -s -`) in CI pipeline
- Uncorked.app: ad-hoc signed (existing behavior)
- PKG: unsigned
- Post-install: `xattr -drs com.apple.quarantine /Applications/Uncorked.app`
- Users need to right-click → Open on first launch (standard for ad-hoc signed apps)

### Phase 2 (Once Apple Developer account is active)

- Engine binaries: signed with Developer ID Application in CI
- Uncorked.app: signed with Developer ID Application + hardened runtime + notarized
- PKG: signed with Developer ID Installer + notarized
- Post-install xattr strip: removed (no longer needed)
- Gatekeeper passes cleanly, no user workarounds

Phase 2 is a CI credentials change only. No architectural changes to the pipeline or app.

## Sparkle Update Flow

- `appcast.xml` updated to point to `Uncorked-X.Y.pkg` (not DMG)
- Sparkle downloads and runs the PKG silently in the background
- User sees: "Uncorked X.Y is available. Restart to update." — nothing about the engine
- Sparkle's existing integration in the app is unchanged

## What Users Experience

**Installing for the first time:**
1. Download `Uncorked.pkg` (~200MB)
2. Double-click, click through macOS install screens
3. Uncorked appears in /Applications, fully ready
4. Right-click → Open on first launch (Phase 1 only; gone in Phase 2)

**Getting an update:**
1. Uncorked shows a non-blocking banner: "Uncorked X.Y is available"
2. User clicks Update
3. Sparkle downloads and installs silently
4. App restarts on the new version
5. User has no idea the engine changed — they just have a newer Uncorked

**No user ever sees:** Wine, engine, wine64, uncorked64, Gcenx, or any internal component name.

## Files Affected (Summary)

| File | Action |
|------|--------|
| `Uncorked/Views/Setup/UncorkedWineDownloadView.swift` | Delete |
| `UncorkedKit/.../UncorkedWine/UncorkedWineInstaller.swift` | Rename → UncorkedEngine.swift, gut and rewrite |
| `UncorkedKit/Sources/UncorkedKit/Wine/Wine.swift` | Update bin path references |
| `.github/workflows/wine-update-check.yml` | Rename → engine-update-check.yml, extend to trigger bundle pipeline |
| `.github/workflows/release.yml` | Replace DMG build with PKG build |
| `CLAUDE.md` | Update with final version mapping scheme and new file structure |
| New: `.github/workflows/engine-bundle.yml` | The full bundle pipeline (steps 1-12 above) |
| New: `scripts/postinstall` | PKG post-install script (extraction + xattr) |
| New: `scripts/generate-wrappers.sh` | Generates uncorked64 etc. wrapper scripts |
