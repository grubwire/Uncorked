# Checkpoint D — shipped 2026-05-28

Cloud-hosted engine delivery validated end-to-end. A fresh Mac with no engine on disk
launches Crosswire.app, autonomously pulls the patched engine from `data.grubwire.io`,
verifies its signature, installs it, and is ready to run Windows apps. The engine
itself ships every patch our CI applies (CW 20760, 22131, 23427, 24256, 24945, 25719,
18947) and the protocol-matched wineserver.

## Verification table

| Check | Result | Evidence |
|---|---|---|
| 5 R2 secrets populated, current | ✓ | `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, `ENGINE_MANIFEST_SIGNING_KEY` — last updated 2026-05-24/25 |
| `engine-promote-prod.yml` artifact shape matches `engine-bundle.yml` output | ✓ | Both expect `Crosswire-engine-${TAG}.tar.xz` + `engine-manifest.json` + `.sig`, archive uploaded before manifest (no dangling pointer window) |
| App URL contract matches workflow upload paths | ✓ | App reads `https://data.grubwire.io/engine/prod/engine-manifest.json`; workflow writes to `s3://${R2_BUCKET}/engine/prod/engine-manifest.json` |
| `data.grubwire.io` DNS resolves to Cloudflare | ✓ | `104.21.55.103`, `172.67.147.119` |
| Promote workflow run | ✓ | [`26554402853`](https://github.com/grubwire/crosswire/actions/runs/26554402853) success in 19s |
| Manifest URL serves CI-built engine | ✓ | sha256 `d30d404b7e5eab3720133e267fe94abc9c733ba18fe96a113869d38d59722bc2`, sizeBytes 737742848 |
| Sig URL serves correct Ed25519 sig | ✓ | 64 bytes |
| Archive URL serves the tarball | ✓ | `content-type: application/x-tar`, `content-length: 213364908` (213 MB compressed) |
| Ed25519 signature verifies against embedded app public key | ✓ | Verified locally with `Ed25519PublicKey.from_public_bytes(bytes.fromhex(PUB_HEX)).verify(sig, manifest)` — embedded public key is `51c6ffe71ee5c92539aeb87c3b348e9b5914f7c03c3811da09be60b06cd822fc` in `EngineManifest.swift` |
| Fresh-install: app autonomously downloaded engine | ✓ | `EngineSetupView.onAppear` → `startSetup()` ran without user interaction |
| Installed `ntdll.so` sha matches CI build | ✓ | `7fccb1ece19414444deba6c78cb76fa19efee1584b228e050783dd475da82d99` on both sides |
| All 4 CW HACK marker strings in installed `ntdll.so` | ✓ | `emulated an XGETBV instruction` (CW 23427), `faking success` (CW 22131), `HACK: write fault on a w\|x page` (CW 24945), `HACK: exec fault on executable page` (CW 25719) |
| `wineserver` co-rebuilt to match `ntdll.so` protocol | ✓ | sha `e2022e5027433299b9fbe923bdc9a2f21496c610846ae28863858abf77b7c7e6` shipped; `wineboot --init` clean (zero `try_map_free_area`, zero version-mismatch errors) |
| `wow64cpu.dll` (CW 20760) shipped | ✓ | sha `bf8d1203c8eb4e7f2ccc1cc7e8cf026ff14e469c9b4fb9bca53da2fe13263a0a`, differs from Gcenx baseline |
| Engine bundle CI run validating SWG | ✓ | [`26553021418`](https://github.com/grubwire/crosswire/actions/runs/26553021418) — the artifact promoted |
| `engine-version.txt` bumped to `11.9` in repo | ✓ | Updated by `engine-promote-prod.yml` automated commit |

## Pipeline shape

1. `engine-bundle.yml` (manual dispatch) clones `Gcenx/wine` at the tag matching the
   Gcenx prebuilt release, applies every `scripts/patch-*.py`, derives the rebuild
   list from `+++ b/<path>` lines in `scripts/patches/*.patch`, builds and swaps the
   affected dylibs, co-rebuilds `wineserver`, verifies marker strings post-swap, signs
   the manifest, uploads artifact.
2. Human inspects artifact (download from Actions, smoke test locally).
3. `engine-promote-prod.yml` (manual dispatch) takes the validated artifact's run ID,
   uploads the archive to `s3://${R2_BUCKET}/engine/prod/archives/` first, then the
   manifest + sig to `s3://${R2_BUCKET}/engine/prod/` with `Cache-Control: no-cache`.
4. App on first launch fetches the manifest, verifies the Ed25519 sig against the
   embedded public key, fetches the archive, verifies the SHA-256, extracts to
   `~/Library/Application Support/app.Crosswire.Crosswire/Engine/`, writes
   `engine-version.json` next to it.

## Known asterisks (not blocking Checkpoint D)

- **Same-version overwrite has no upgrade signal for existing users.** The prod
  manifest pre-existed at `engineVersion: "11.9"` with a different sha. Promoting our
  new artifact overwrites it but existing users on the old 11.9 don't auto-update
  because the engine-update logic compares the version string only. Next engine bump
  should land as `11.9.1` (or similar) so the version-string comparison forces an
  update for in-the-wild installs.
- **Bug #91** — `JavaAppDetector` plist auto-seed doesn't fire during the GUI install
  flow because `ProgramSettings.decode` writes an empty default plist on first read,
  which trips JavaAppDetector's respect-existing-plist guard. dwrite override still
  fires (separate code path). Filed: <https://github.com/grubwire/crosswire/issues/91>.
- **VERSIONINFO auto-naming gap** — bottle displays its source-exe stem instead of
  the VS_VERSIONINFO ProductName during the GUI install flow. Smoke tests confirmed
  the parser works in isolation; root cause TBD. Filed as separate issue.
