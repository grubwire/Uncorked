# Overnight session — 2026-05-27 (2:30am → ~3:30am)

Mac-side agent worked through both tracks. Everything pushed to `main`
unless explicitly noted. Read this top-to-bottom before doing anything.

---

## TL;DR

| Track | Item | Status |
|-------|------|--------|
| Bug fix | Env-var routing on every launch path | ✅ shipped (`eeaf999`) |
| UX pass 1 | Pin tiles, BottleView library section, empty states | ✅ shipped (`5e36619`) |
| UX pass 2 | "Install common runtimes" sheet | ✅ shipped (`56f9b59`) |
| SWG-A | Verify download | ⚠️ launcher running; download not started |
| SWG-B | Vulkan rebuild | 🚧 prepped, blocked on Vulkan SDK |
| Failure-reporting | Stale install-alert copy | ✅ included in `eeaf999` |
| Bottle naming | Hide "bottle" word in alerts | ✅ included in `eeaf999` |

The big-win commit is `eeaf999`. Read its body — it explains
exactly why the SWG launcher sliver-render kept coming back.

---

## What changed in the app (and what to test in the morning)

### 1. Env-var routing fix — root cause of the SWG sliver-render

`Wine.runProgram(at:bottle:)` had been silently dropping the per-program
plist's environment. Only `program.run()` (Pins + Programs list) honored
it. Every other launch path — drag-and-drop onto a bottle, File > Open,
the install-flow auto-run, AppSettingsSheet's Run button — exec'd the
program with only the bottle-level env vars. That's why `_JAVA_OPTIONS=
-Dprism.order=j2d -Xint` worked from Terminal/Pins but not from the GUI.

Now `Wine.runProgram` always reads `Program Settings/<exe>.plist`
on disk and merges its environment / locale / arguments into the launch.
Caller-supplied env keys still win. Plist absence is the no-op default.

**Test:** rebuild Crosswire.app from Xcode, launch the SWG launcher via
any path (AppSettingsSheet Run, pin double-click, even file-open). It
should render normally — no sliver.

### 2. UX pass 1 — pin tiles, library composition, empty states

- **PinView**: bigger 64pt tile, proper `AppTileIcon` fallback (was a
  bare `app.dashed` system glyph), hover lifts the tile, play badge
  fades in on hover with accent color (was a permanent hardcoded green
  corner badge that fought PE icons). Single-click runs.
- **PinAddView**: dashed-border drop-slot affordance, matches new sizing.
- **AppTileIcon**: vertical gradient + inner top highlight + base-color
  shadow so the tile reads as a real surface, not a flat swatch.
- **BottleView**: reorganized into "LIBRARY" section header + nav-card +
  utility bar with proper icons (folder / terminal / wrench).
- **ContentView empty state**: accent-tinted halo + hierarchical copy
  ("No apps yet" + subhead + large primary button) instead of a single
  centered button. No-match state gets a magnifying-glass glyph.

### 3. Common runtimes installer

New sheet: per-app **Advanced → Install common runtimes…**. Curated
checklist (corefonts, vcrun2019, vcrun2013, dotnet48, d3dx9 recommended
+ older VC++, .NET 4.7.2, D3D compiler, XACT, PhysX optional). Selected
verbs join into one `winetricks` call so it's one Terminal session, not
N.

Catalogue lives in `Crosswire/Utils/RuntimePresets.swift` — easy to
extend.

### 4. Stale alert copy

The "Installer finished but no apps were detected" dialog was guessing
"look for mmap errors" — that was an old diagnosis from before the mmap
layer was fixed. Removed; the alert now just points at the log path.
The "Could not create bottle" alert was rephrased to "Could not set up
\<name\>" (kills another stray "bottle" leak in the primary UI).

---

## SWG track

### Session A — verify download

**Not yet downloaded.** The SWG game client (`SwgClient_r.exe` or
similar) is NOT in `drive_c/Program Files (x86)/StarWarsGalaxies/`.
Only `SWGLegendsLauncher.exe` and the `.tres` archives (which look like
prior patch data, not the client itself). The launcher needs to
successfully reach its "play/ready" state to drive the actual client
download.

The launcher process from last night is still alive at PID 24373
(started 1:29am, ~2h uptime, only 33s of CPU — sitting idle, no outbound
network connections). A second launcher I started at 3:10am attached to
the same wineprefix; its outer `start.exe` wrapper is at PID 46476 and
just blocks waiting for the existing javaw.

**What to do:** rebuild Crosswire.app to pick up the env-var fix, kill
the stale launcher (`pkill -f javaw` or restart the SWG bottle), then
launch via the Crosswire UI. The plist already has both required env
vars — they'll now actually reach the exec, and the launcher should
render normally. Click "Play" to kick the download.

### Session B — Vulkan rebuild

**Blocked on macOS Vulkan SDK / arch mismatch.** Wrote
`scripts/build-vulkan-engine.sh` with full preflight + configure + sign
+ swap pipeline. Validated everything up to the linker step:

- ✅ `/tmp/wine-build/wine-src` patched tree intact
- ✅ `brew install bison mingw-w64 vulkan-headers vulkan-loader` done
- ✅ `pkg-config --modversion vulkan` → `1.4.350`
- ✅ Configure runs cleanly with `--host=x86_64-apple-darwin --enable-win64 --with-vulkan` until…
- ❌ Linker can't find `-lvulkan` / `-lMoltenVK`. Brew's libvulkan.dylib
  is **arm64-only**; the existing engine is x86_64-under-Rosetta. The
  link step fails: *"libvulkan and libMoltenVK 64-bit development files
  not found."*

**Two paths to unblock** (script header documents both):

  **(A) Install LunarG Vulkan SDK for macOS** — ships a universal
  (arm64 + x86_64) libvulkan.dylib + MoltenVK in one DMG. Point
  pkg-config + linker at its install dir before re-running the script.
  Single-day fix.

  **(B) Pivot engine to arm64-native** — `brew install llvm-mingw`,
  then rebuild every Mach-O .so under `dlls/`. Removes the Rosetta
  hop entirely. Multi-day fix but the right long-term direction for
  Apple Silicon.

Until then, `make` is NOT running. I did not kick off a 1.5h build I
know would fail at link.

Script: `scripts/build-vulkan-engine.sh`. Run it after fixing libvulkan
and it'll do the rest end-to-end.

### Session C / D

Blocked behind A + B. Nothing to do until the launcher downloads the
game client and Vulkan is enabled.

---

## What did NOT happen

- **Vulkan rebuild itself** — see above, gated on libvulkan arch.
- **Full failure-reporting feature (exit code → GitHub issue pre-fill)** —
  partial: I did fix the stale-copy gap you flagged. The full "detect
  abnormal exit → assemble report → open pre-filled GitHub issue" flow
  was not built tonight; it needs a redesign of how `Wine.runProgram`
  surfaces exit status to its callers. Notes for the morning:
  - `ProcessOutput.terminated(Process)` already carries the Process; the
    consumer just needs to inspect `terminationStatus`.
  - Detection rule "exits within 10s with no window" needs window-count
    via `NSWorkspace`/wineserver introspection — separate piece.
- **App-identity VERSIONINFO fallback** — the existing chain (Start Menu
  → registry uninstall DisplayName → installer filename) covers most
  installers; adding PE VS_VERSIONINFO between #1 and #2 needs a PE
  resource-parser extension. Out of scope tonight.
- **Auto-install common runtimes on new bottle creation** — opt-in
  toggle in Settings was sketched but not built. The manual sheet
  shipped instead (it covers the immediate "I just installed
  something and it can't find vcruntime140.dll" pain).

---

## State of the working tree

```
git log --oneline -7
56f9b59 Add "Install common runtimes" sheet for one-click Windows dependencies
5e36619 UX: tactile pin tiles, library section in BottleView, empty-state polish
eeaf999 Apply per-program plist env on every launch path; destale install copy
40f8c5f Refresh QuickLook thumbnail icon to match current app logo
9872059 Silence SwiftLint warnings in Process+Extensions
dd38649 Updated SettingsView and Main to use new Process extension for running commands. ...
74794bd Move app icons out of repo root, into Crosswire/
```

All three of my commits are pushed to `origin/main`. `build-vulkan-engine.sh`
is in the next commit (this file + the script).

`/tmp/crosswire-overnight/` holds the launcher stdout (empty — output
went through wineserver) and `xcodebuild.log`.

`/tmp/wine-build/build-vulkan-probe/` is the throwaway probe build dir.
Safe to `rm -rf`.

---

## First three things to do when you wake up

1. **Rebuild Crosswire.app in Xcode** (any path that lands a fresh build
   into `/Applications` or runs from Xcode). Your existing running app
   does NOT have the env-var fix yet. Until you rebuild, the SWG
   launcher will still sliver-render.
2. **Kill the stale SWG launcher** (`pkill -f javaw`) and re-launch
   from Crosswire's UI. Confirm it renders. If it does, click Play and
   let the game client download.
3. **Decide on Vulkan path A vs B**. Install LunarG SDK or commit to
   the arm64 pivot. Once libvulkan resolves, `bash scripts/build-vulkan-engine.sh`
   runs the rest unattended.
