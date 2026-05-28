# Milestone — SWG Legends launcher confirmed end-to-end on cloud-served engine

**Date:** 2026-05-28
**Bottle:** `7F4FF523-320B-46D5-B80F-855B425B1004`

The SWG Legends launcher reached the post-Login state — Update button reachable — on
a Crosswire installation where every piece of the engine came from
`data.grubwire.io`, not from a local dev build. This is the first time the full
"fresh user with nothing pre-installed gets SWG running" chain was proven on this
hardware.

## Chain proven

1. Fresh local state: `~/Library/Application Support/app.Crosswire.Crosswire/Engine/`
   and `engine-version.json` removed.
2. Crosswire.app launched. `EngineSetupView.startSetup()` fired on `.onAppear`,
   no user click required.
3. App fetched manifest from `https://data.grubwire.io/engine/prod/engine-manifest.json`.
4. App verified Ed25519 signature against embedded public key.
5. App fetched archive `https://data.grubwire.io/engine/prod/archives/Crosswire-engine-11.9.tar.xz`
   (213 MB compressed).
6. App verified SHA-256 against the manifest's `sha256` field.
7. App extracted to `Engine/`, wrote `engine-version.json`.
8. Engine on disk: `ntdll.so` sha exact match to CI build; all four CW HACK marker
   strings present (XGETBV, faking-success, write-fault, exec-fault).
9. User clicked **Install Windows App** → picked `~/Downloads/SWGLegendsSetup.exe` →
   bottle `7F4FF523` created, installer ran the SWG install wizard, `Program Files
   (x86)/SWG Legends/` populated with launcher + sibling `lib/jre/` tree.
10. `dwrite=builtin` registry override auto-applied to the bottle by
    `JavaAppDetector` during install.
11. `AeDebug=0` auto-applied at bottle creation by `Wine.disableCrashDebugger`.
12. User clicked **Run** in Crosswire → launcher rendered → typed creds → clicked
    **Login** → **login succeeded** → launcher displayed "Update available."

## Engine binaries in flight at the time of Login success

| Binary | Source | sha256 |
|---|---|---|
| `Engine/lib/wine/x86_64-unix/ntdll.so` | CI build of patched `Gcenx/wine` 11.9 | `7fccb1ece19414444deba6c78cb76fa19efee1584b228e050783dd475da82d99` |
| `Engine/lib/wine/x86_64-windows/wow64cpu.dll` | same | `bf8d1203c8eb4e7f2ccc1cc7e8cf026ff14e469c9b4fb9bca53da2fe13263a0a` |
| `Engine/bin/wineserver` | same | `e2022e5027433299b9fbe923bdc9a2f21496c610846ae28863858abf77b7c7e6` |

CW patches active in the running launcher's address space: 20760 (WoW64 lretq thunk),
22131 (debug-register fake success), 23427 (XGETBV emulation), 24256 (Rosetta-cache),
24945 + 25719 (W\|X mprotect toggles), 18947 (NtWriteVirtualMemory exec-bit invalidate).

## Known asterisks at the milestone

- **`_JAVA_OPTIONS` plist auto-seed did NOT fire on this install.** Plist had an empty
  `environment` dict; was manually patched before clicking Run to add
  `_JAVA_OPTIONS=-Dprism.order=j2d -Xint`. The Login click would have failed without
  this patch. Bug #91 captures the root cause (`ProgramSettings.decode` write-on-first-read
  side effect tripping JavaAppDetector's skip-existing guard). <https://github.com/grubwire/crosswire/issues/91>
- **VERSIONINFO auto-naming did NOT fire on this install.** Bottle shows as
  `SWGLegendsLauncher` (source-exe stem) rather than the VS_VERSIONINFO ProductName
  `SWG Legends Launcher`. The parser works correctly in standalone smoke tests, so
  something specific to the SWG install path bypassed it. Filed as separate issue.
- **dwrite override DID fire automatically.** Same install flow, same JavaAppDetector
  call site — but the registry write went through where the plist write was blocked.
  This asymmetry is the diagnostic clue for the auto-flow ordering bug (see
  follow-up investigation).
- **Post-login crash separately tracked in #84.** Out of scope tonight; predates the
  cloud-engine work and is downstream of Login.
- **The SWG launcher zip-vs-bare-exe gap.** Crosswire's install flow handles `.exe`,
  `.msi`, `.bat`. Apps distributed as `.zip` (a `.exe` plus required sibling files)
  aren't handled — user has to extract first, then pick the installer or launcher.
  Crossover supports zip drops; captured for backlog.

## Reproduction

```
# 1. clear local engine
rm -rf ~/Library/Application\ Support/app.Crosswire.Crosswire/Engine
rm -f ~/Library/Application\ Support/app.Crosswire.Crosswire/engine-version.json

# 2. launch Crosswire.app — engine downloads + installs autonomously

# 3. in Crosswire: Install Windows App -> ~/Downloads/SWGLegendsSetup.exe
#    (the installer, not the bare launcher .exe)

# 4. installer wizard runs; bottle created; auto-features fire (dwrite is the only
#    one currently firing reliably; see asterisks)

# 5. apply the bug #91 workaround until that bug is fixed:
#    plutil -replace 'environment._JAVA_OPTIONS' -string "-Dprism.order=j2d -Xint" \
#      "$BOTTLE/Program Settings/SWGLegendsLauncher.exe.plist"

# 6. click Run in Crosswire -> launcher renders -> type creds -> Login -> success
```
