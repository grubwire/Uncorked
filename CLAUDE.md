# Uncorked - Project Context for Claude

## What Uncorked Is

Uncorked is a standalone macOS app for running Windows software. It is a fork of
[Whisky](https://github.com/Whisky-App/Whisky), fully rebranded in May 2026.
Published by Grubwire (grubwire.io) under GPL-3.0.

**There is no "Wine" in Uncorked. There is no "engine" visible to users. There is only Uncorked.**

The Windows compatibility engine (Wine, sourced from Gcenx) is an internal implementation
detail. Users install Uncorked, it works. That is the entire experience.

## Two-Stage Strategy

- **Stage 1 (current): Cloud Download.** Small DMG (~10-20 MB); engine downloaded on first
  launch from data.grubwire.io, installed to Application Support. Build this now.
- **Stage 2 (future): Bundled Engine.** Engine ships inside app bundle. Do not start this.

Do NOT build the beta system (dev/beta/prod pipeline, in-app toggle) yet. Stage 1 ships
single-channel (prod only) and is built beta-ready per the checklist in the implementation
plan.

## Current Architecture (Stage 1 - cloud-hosted engine)

```
Uncorked (SwiftUI app)
└── UncorkedKit (Swift package, local dependency)
    ├── Engine/         - UncorkedEngine, RosettaCheck, EngineManifest
    ├── Wine/           - Wine process management (class name Wine kept for internal use)
    ├── Uncorked/       - Bottle, Program, BottleSettings models
    ├── PE/             - PE binary parsing
    └── Extensions/     - Swift extensions

R2 layout (data.grubwire.io):
  engine/
    prod/
      engine-manifest.json      - signed manifest (mutable, always latest)
      engine-manifest.json.sig  - Ed25519 signature
      archives/
        uncorked-engine-11.9.tar.xz   - immutable, version-specific
        uncorked-engine-11.8.tar.xz   - prior versions retained for rollback
    staging/                          - DEBUG build target (same structure)
  beta/                               - NOT yet created (Part 2 of the plan)

Engine installed at: ~/Library/Application Support/Uncorked/Engine/
  bin/    - uncorked64 (wrapper), uncorkedserver, uncorkedboot, wine64, wineserver, etc.
  lib/    - .dylib and Mach-O .so files
  share/
engine-version.json  (sibling to Engine/, in Application Support/Uncorked/)
```

## How the Engine Gets to Users

1. `engine-update-check.yml` (weekly cron): compares `engine-version.txt` to latest Gcenx tag.
   Opens a GitHub issue if a newer version is available.
2. Human reviews the Gcenx release, then runs `engine-bundle.yml` via the Actions tab.
3. `engine-bundle.yml`: downloads from Gcenx, generates wrappers, signs all Mach-O files
   (Phase 1: ad-hoc), repacks, runs boot smoke test, generates and signs
   `engine-manifest.json`, uploads as a GitHub Actions artifact. Does NOT auto-publish.
4. Human tests the artifact (fresh install, bottle creation, known .exe).
5. Human runs `engine-promote-prod.yml` to upload the validated artifact to R2 prod and
   update `engine-version.txt` in the repo.
6. App fetches manifest on first launch, verifies Ed25519 signature, downloads engine,
   verifies SHA-256, checks disk space, extracts to Application Support, clears quarantine,
   writes `engine-version.json`.

## Engine Manifest Format

```json
{
  "schemaVersion": 1,
  "engineVersion": "11.9",
  "upstreamTag": "11.9",
  "url": "https://data.grubwire.io/engine/prod/archives/uncorked-engine-11.9.tar.xz",
  "sha256": "<hex SHA-256 of archive>",
  "sizeBytes": <uncompressed engine size in bytes>,
  "minAppVersion": "1.0.0"
}
```

Manifest is signed with Ed25519 (CryptoKit `Curve25519.Signing`).

- Public key (embedded in `EngineManifest.swift`): `51c6ffe71ee5c92539aeb87c3b348e9b5914f7c03c3811da09be60b06cd822fc`
- Private key (hex seed): stored in GitHub secret `ENGINE_MANIFEST_SIGNING_KEY`
  - PEM backup at `~/.engine-manifest-key.txt` on nick-dev-01 (NOT in repo)
  - Key rotated 2026-05-24 (second rotation; prior seed exposed in session transcript)
  - To sign: `bash scripts/sign-manifest.sh /path/to/engine-manifest.json`

## Engine Version State

Installed engine state is written to:
`~/Library/Application Support/Uncorked/engine-version.json`

```json
{
  "engineVersion": "11.9",
  "upstreamTag": "11.9"
}
```

The `UncorkedEngineVersion.plist` used by older builds is legacy. The migration cleanup
`removeLegacyEngineIfNeeded()` removes stale `Libraries/Wine` from pre-managed installs.

## Gcenx: The Engine Upstream

Gcenx (GitHub: `Gcenx/macOS_Wine_builds`) compiles Wine for macOS with Apple Silicon patches.

### Asset Naming (as of 2026-05, release 11.9)

wine-stable was dropped. Only `wine-staging` and `wine-devel` exist.

Asset priority: `wine-stable-*` > `wine-staging-*` > `wine-devel-*` > any `.tar.xz`

Tag format: bare version number (`11.9`), no prefix.

Asset sizes: ~190MB tar.xz each.

## Signing Rules — Critical

**NEVER use `codesign --force --deep`.** It is deprecated and unreliable.

Sign every Mach-O file individually, inside-out, detected by `file` not extension:
1. All `.dylib` files anywhere in the engine tree
2. All Mach-O `.so` files under `lib/wine/` (Wine builtins, Mach-O on macOS)
3. All Mach-O executables under `bin/` and anywhere else
4. Skip: shell wrapper scripts, PE `.dll` files, data files

The signing script: `scripts/sign-engine.sh`

### Phase 1 (current, no Developer ID)

- `IDENTITY=-` (ad-hoc), no `--options runtime`, no entitlements
- Ad-hoc is sufficient for Apple Silicon; every Mach-O must be signed or it is killed on launch
- Gatekeeper on macOS 15+ Sequoia: user must go to System Settings > Privacy & Security >
  "Open Anyway" on first launch. Right-click Open bypass was removed in Sequoia.

### Phase 2 (future, requires Apple Developer account)

- `IDENTITY="Developer ID Application: ..."`, `--options runtime --timestamp`
- Add `scripts/engine.entitlements` with Wine exception entitlements:
  `cs.allow-unsigned-executable-memory`, `cs.disable-library-validation`,
  `cs.allow-dyld-environment-variables`
- Enable `ENABLE_HARDENED_RUNTIME = YES` in Xcode release config
- Notarize app, staple, notarize DMG, staple DMG
- Phase 2 is NOT a pure credentials swap; entitlements file and Xcode config changes required
- Only Developer ID Application cert needed (DMG-only distribution)

## Distribution

**DMG only.** One artifact for both first install and Sparkle updates.

Sparkle uses DMG-based app replacement (no admin prompt). Do not use PKG-based Sparkle updates.

## Version Scheme

Uncorked app version is fully decoupled from engine version. Engine version never appears in
the app's version string.

- Engine updates do not require app updates and vice versa.
- Currently published prod engine tag recorded in `engine-version.txt` (repo root, updated by
  `engine-promote-prod.yml`).
- Installed engine state in `engine-version.json` under Application Support.

## Key Files

| File | Purpose |
|------|---------|
| `UncorkedKit/.../Engine/UncorkedEngine.swift` | Engine install, verify, update check, bin paths |
| `UncorkedKit/.../Engine/EngineManifest.swift` | Manifest model, Ed25519 verification, SHA-256 |
| `UncorkedKit/.../Engine/RosettaCheck.swift` | Apple Silicon detection, Rosetta install |
| `Uncorked/Views/Setup/EngineSetupView.swift` | Unified download + verify + install setup UI |
| `Uncorked/Views/About/AboutView.swift` | About/Acknowledgements: Wine, Gcenx, DXVK, Whisky |
| `Uncorked/Views/About/DiagnosticsView.swift` | Diagnostics: app version, engine version, beta state |
| `scripts/sign-engine.sh` | Inside-out Mach-O signing (Phase 1 and 2) |
| `scripts/sign-manifest.sh` | Signs engine-manifest.json with Ed25519 private key |
| `scripts/generate-wrappers.sh` | Generates uncorked64, uncorkedserver, uncorkedboot |
| `engine-version.txt` | Currently published prod engine tag (updated by CI on promotion) |
| `.github/workflows/engine-bundle.yml` | Build, sign, smoke test, GitHub artifact (no auto-publish) |
| `.github/workflows/engine-promote-prod.yml` | Manual promotion of validated artifact to R2 prod |
| `.github/workflows/engine-update-check.yml` | Weekly check for new Gcenx releases |
| `.github/workflows/release.yml` | App build, sign, DMG, GitHub release |

## Prod Promotion Workflow

Prod promotion is always a manual decision:
1. `engine-bundle.yml` produces an artifact (archive + manifest + signature).
2. Human tests the artifact.
3. Human runs `engine-promote-prod.yml` with the tag and run ID.
4. Workflow uploads archive to `engine/prod/archives/` first, then overwrites the manifest
   (so the manifest never points at a missing object).
5. Prior archives are retained; rollback = reverting the prod manifest to a prior version.

## Beta-Ready Checklist (Stage 1 must satisfy these)

These ensure the beta system (Part 2) can be added later without migration:

1. R2 layout is tiered (`engine/prod/...`) from day one. Adding `engine/beta/...` is a new prefix.
2. Engine manifest URL is one isolated config constant in `EngineManifest.swift` (not scattered).
3. Sparkle appcast URL is one isolated config value (for future beta appcast).
4. Diagnostics view exists from Stage 1 (app version, engine version, beta state "off").
5. Prod promotion is a separate manual workflow (`engine-promote-prod.yml`).

Status: all five items are satisfied.

## Checkpoint D (R2 / data.grubwire.io setup)

**Requires Nick's Cloudflare account.** Steps needed:
1. Create an R2 bucket (e.g. `uncorked-engine`) with public access on `engine/prod/` and
   `engine/staging/` prefixes.
2. Bind `data.grubwire.io` as a custom domain on the bucket (not just the zone).
3. Add GitHub secrets: `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`
4. Add `ENGINE_MANIFEST_SIGNING_KEY` (hex private key seed) to GitHub secrets.
5. Run `engine-bundle.yml` to produce the first artifact.
6. Run `engine-promote-prod.yml` to publish to prod.
7. Verify the app downloads the engine on a fresh install.

Until Checkpoint D is done, first-run installs fail at the engine download step (EngineSetupView
shows the error and a Retry button).

## Migration (existing users)

On first launch after upgrade, `removeLegacyEngineIfNeeded()` runs once and removes the stale
engine at `Libraries/Wine` only if `engine-version.json` is absent (pre-managed install).
Bottles and wineprefixes are preserved.

## Internal Naming Rules

- All Swift code uses `uncorked64` (the wrapper), never `wine64` directly.
- `Wine.wineBinary` points to `Engine/bin/uncorked64`.
- `Wine.wineserverBinary` points to `Engine/bin/uncorkedserver`.
- No user-facing strings mention Wine, engine, wrappers, or internal version numbers.
- The `Wine` class in `Wine.swift` keeps its name internally (user decision, backward compat).
- Winetricks is a proper noun kept throughout.
- `wineVersion` remains the persisted `BottleSettings` key (backward compat with existing bottles).

## Signing Phase 1 to Phase 2 Transition

Do NOT regenerate the Sparkle EdDSA key. Test ad-hoc to Developer ID update path explicitly
before relying on it. Include direct DMG link in the transition release notes.

## Whisky Reference

Uncorked is a fork of Whisky. For reference: `https://github.com/Whisky-App/Whisky`
