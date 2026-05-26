# Crosswire UX Redesign: Exe-First Flow

**Status:** Deferred. Do not implement until the SWG installer `.exe` failure is diagnosed and the "run an .exe" flow is confirmed reliable end-to-end.

---

## 1. Context

Crosswire's stated design principle is that the engine is invisible to the user. The current UI violates the parallel principle for bottles: a user must explicitly create and name a bottle before they can run any `.exe`. This is an implementation detail surfaced as a prerequisite step, which contradicts the product's goal of making Windows app execution feel native and frictionless on macOS. The redesign extends the "engine-is-invisible" principle to bottles: a bottle is a consequence of running an `.exe`, not a precondition the user manages. The primary redesign work is the app-level UX layer; the underlying `Wine.runProgram` and `BottleVM.createNewBottle` machinery already exists and does not need to be replaced, only wrapped by a new auto-provision layer.

---

## 2. Current Architecture

### How a user runs a program today

**Step 1: Create a bottle**

The user clicks the `+` toolbar button in `Crosswire/Views/ContentView.swift:60-65`, which sets `showBottleCreation = true` and presents `BottleCreationView` as a sheet (`ContentView.swift:116-118`).

`Crosswire/Views/Bottle/BottleCreationView.swift:22-96` collects three inputs: bottle name (required), Windows version (picker, defaults to Win10), and storage directory (defaults to `BottleData.defaultBottleDir`). On submit (`BottleCreationView.swift:90-95`), it calls `BottleVM.shared.createNewBottle(bottleName:winVersion:bottleURL:)`.

`Crosswire/View Models/BottleVM.swift:38-68` creates a UUID-named subdirectory under the chosen path, instantiates a `Bottle` object with `inFlight: true`, appends it to `bottlesList.paths`, calls `Wine.changeWinVersion` to initialize the wineprefix, and then calls `loadBottles()`. A freshly initialized wineprefix is approximately 700 MB on disk.

**Step 2: Select the bottle, then run an .exe**

After creation, `ContentView.swift:199-207` auto-selects the new bottle URL in the sidebar. The user then sees `BottleView` in the detail pane.

`Crosswire/Views/Bottle/BottleView.swift:75-106` has a "Run" button in the bottom bar that opens `NSOpenPanel` filtered to `.exe`, `.msi`, and `.bat`, defaulting to `bottle.url/drive_c`. On file selection it calls `Wine.runProgram(at:bottle:)`.

`CrosswireKit/Sources/CrosswireKit/Wine/Wine.swift:101-113` (`runProgram`) runs `Crosswire64 start /unix <path>` with `WINEPREFIX` set to `bottle.url.path`.

**Step 3: Find installed programs afterward**

`BottleView.swift:148-164` (`updateStartMenu`) calls `bottle.updateInstalledPrograms()` and `bottle.getStartMenuPrograms()` on `onAppear`.

`Crosswire/Extensions/Bottle+Extensions.swift:115-142` (`updateInstalledPrograms`) walks `drive_c/Program Files` and `drive_c/Program Files (x86)`, collecting `.exe` files not on the blocklist, and replaces `bottle.programs`.

`Bottle+Extensions.swift:57-113` (`getStartMenuPrograms`) walks the global and user Start Menu directories for `.lnk` files, resolves them via `ShellLinkHeader.getProgram`, and returns `Program` objects.

Programs appear in `Crosswire/Views/Programs/ProgramsView.swift` via a `NavigationLink` in `BottleView.swift:50-52`. Individual program details and the relaunch button live in `Crosswire/Views/Programs/ProgramView.swift:78-89`.

**What FileOpenView does**

`Crosswire/Views/FileOpenView.swift` is the `onOpenURL` handler path (`ContentView.swift:131-133`). When an `.exe` is opened externally, Crosswire presents a picker asking the user to choose which existing bottle to run it in (`FileOpenView.swift:32-38`). If only one bottle exists it auto-selects and runs immediately (`FileOpenView.swift:63-74`). If zero bottles exist it dismisses itself (`FileOpenView.swift:62-64`). This path has no auto-provisioning logic.

**Empty state**

`ContentView.swift:219-235`: when no bottles exist, the detail pane shows `Text("main.createFirst")` and a "Create Bottle" button. The sidebar is empty. There is no primary call-to-action visible on first launch directing the user to run an `.exe`.

**First-run / setup**

`Crosswire/Views/Setup/WelcomeView.swift` covers Rosetta and engine installation. It does not address bottles or the `.exe` flow. Once setup completes the user lands on the empty bottle-list state described above.

---

## 3. Target User Flow

### Flow A: First launch, engine not yet installed

| Step | What happens | Responsible file |
|---|---|---|
| 1 | App launches, engine absent, `showSetup = true` | `ContentView.swift:146-150` |
| 2 | Setup sheet runs Rosetta + engine download | `SetupView`, `EngineSetupView.swift` |
| 3 | Setup completes, sheet dismisses | `WelcomeView.swift:79-91` |
| 4 | Main window shows new empty state with "Run an .exe" CTA | `ContentView.swift` (modified detail pane) |

### Flow B: First launch, engine installed, no apps yet

| Step | What happens | Responsible file |
|---|---|---|
| 1 | App loads, `bottlesLoaded = true`, no bottles | `ContentView.swift:134-145` |
| 2 | Detail pane shows empty state with "Run an .exe" primary button | `ContentView.swift:219-235` (modified) |
| 3 | User clicks button, file picker opens (`.exe`, `.msi`, `.bat`) | `RunExeView.swift` (new) |
| 4 | User picks file; `BottleAutoProvision` creates a bottle, runs `Wine.runProgram` | `BottleAutoProvision.swift` (new) |
| 5 | Crosswire minimizes so the launched window comes forward | `BottleAutoProvision` calls `NSApp.miniaturize(nil)` before process start |
| 6 | Process terminates; `updateInstalledPrograms()` runs; bottle appears in sidebar | `BottleAutoProvision` post-run callback |

### Flow C: Re-launching an installed app

| Step | What happens | Responsible file |
|---|---|---|
| 1 | User opens Crosswire; bottles listed in sidebar | `ContentView.swift` sidebar |
| 2 | User clicks program's run button | `ProgramItemView` in `ProgramsView.swift:185-190` or `ProgramView.swift:78-89` |
| 3 | `program.run()` calls `Wine.runProgram` for the stored URL | `CrosswireKit/Sources/CrosswireKit/Extensions/Program+Extensions.swift` |
| 4 | Crosswire minimizes; app window comes forward | `NSApp.miniaturize(nil)` added at run call sites |

### Flow D: Run another .exe with existing bottles

| Step | What happens | Responsible file |
|---|---|---|
| 1 | User clicks "Run an .exe" in toolbar or File menu | `ContentView.swift` toolbar (modified) |
| 2 | File picker opens | `RunExeView.swift` |
| 3 | `BottleAutoProvision` provisions a new bottle and runs the file | `BottleAutoProvision.swift` |

---

## 4. Recommended Answers to Open Questions

### Bottle-per-app vs shared bottle

**Recommendation: one bottle per provisioned `.exe`.**

A shared bottle accumulates DLL overrides, registry changes, and Program Files content from every installer run in it. Diagnosing failures becomes harder with every additional app. Per-app bottles are isolated by default and can be deleted without affecting other apps.

Disk cost: a freshly initialized Win10 wineprefix is approximately 700 MB. Each bottle costs that baseline plus whatever the installed app writes. A shared bottle saves one baseline (~700 MB) for each additional app but introduces conflict risk. The per-app cost is acceptable; the conflict risk of a shared bottle is not.

Naming scheme: use the stem of the `.exe` filename (e.g. `SWGSetup.exe` produces a bottle named `SWGSetup`). Append a counter suffix if a bottle with that name already exists (`SWGSetup 2`, etc.).

### Installer vs standalone detection

**Recommendation: run, observe, classify after the fact.**

Pre-run classification based on filename or PE metadata is unreliable. The correct approach:

1. Immediately after bottle creation (before `runProgram`), snapshot the file paths present in `drive_c/Program Files` and `drive_c/Program Files (x86)`. Both directories are empty at this point in a fresh bottle.
2. Run the `.exe` via `Wine.runProgram`. Await completion.
3. Call `bottle.updateInstalledPrograms()` and `bottle.getStartMenuPrograms()`.
4. If `getStartMenuPrograms()` returns `.lnk`-resolved programs, those are the relaunchable entries; pin them automatically.
5. If `updateInstalledPrograms()` discovers `.exe` files in Program Files that were not in the before-snapshot, pin those.
6. If neither produces entries, treat the original `.exe` as the relaunchable app and pin it directly.

This approach correctly handles installers that write to Program Files, installers that only write Start Menu entries, and standalone executables that do neither.

### Finder integration

Confirmed deferred. "Open With Crosswire" from Finder requires `CFBundleDocumentTypes` and `UTImportedTypeDeclarations` entries in `Info.plist` and updates to `CrosswireApp.swift:54`. This is a self-contained task. The existing `onOpenURL` path in `ContentView.swift:131-133` and `FileOpenView.swift` can be kept as-is until the Finder integration task is scoped separately.

---

## 5. File-Level Change List

### New files

| Path | Status | Description |
|---|---|---|
| `CrosswireKit/Sources/CrosswireKit/Crosswire/BottleAutoProvision.swift` | A | Service layer. Takes a source `.exe` URL. Generates a bottle name from the file stem with collision handling. Calls `BottleVM.createNewBottleAsync`, waits for the bottle to leave `inFlight` state. Takes a before-snapshot of Program Files paths. Calls `Wine.runProgram`. Takes an after-snapshot. Calls `updateInstalledPrograms()` and `getStartMenuPrograms()`. Pins discovered programs. Returns the provisioned `Bottle` and discovered `[Program]`. Lives in CrosswireKit so it is accessible from both the app and any future CLI path. |
| `Crosswire/Views/RunExeView.swift` | A | Thin SwiftUI view. Wraps the `NSOpenPanel` call for picking `.exe` / `.msi` / `.bat`. Hands the selected URL to `BottleAutoProvision`. Shows an indeterminate progress indicator while provisioning. Dismisses after programs are pinned and the bottle is ready. |

### Modified files

| Path | Status | Description |
|---|---|---|
| `Crosswire/Views/ContentView.swift` | M | Replace the empty-state detail pane (`ContentView.swift:219-235`) with a centered "Run an .exe" primary CTA. Add a `showRunExe: Bool` state and `.sheet(isPresented:)` binding to `RunExeView`. The `+` toolbar button that opens `BottleCreationView` is moved to the ellipsis menu or `File > New Bottle` to de-emphasize it. |
| `Crosswire/Views/FileOpenView.swift` | M | Fix the zero-bottles path at `FileOpenView.swift:62-64`: instead of dismissing, call `BottleAutoProvision` to create a bottle and run the file. |
| `Crosswire/View Models/BottleVM.swift` | M | Add `createNewBottleAsync` that returns a `Bottle` after `inFlight` drops to `false`, so `BottleAutoProvision` can sequence bottle-ready before calling `Wine.runProgram`. The existing synchronous `createNewBottle` remains for the manual creation sheet. |
| `Crosswire/Views/Bottle/BottleView.swift` | M | Call `NSApp.miniaturize(nil)` immediately before the `Wine.runProgram` call in the Run button handler (`BottleView.swift:85-103`). Also run `updateStartMenu()` after `runProgram` completes, not only on `onAppear`. |
| `Crosswire/Views/Programs/ProgramsView.swift` | M | Add `NSApp.miniaturize(nil)` before `program.run()` at `ProgramsView.swift:185-190`. |
| `Crosswire/Views/Programs/ProgramView.swift` | M | Add `NSApp.miniaturize(nil)` before `program.run()` at `ProgramView.swift:80`. |
| `Crosswire/Views/Bottle/BottleCreationView.swift` | M | No logic changes. The view is de-emphasized from the primary toolbar but not deleted. It remains accessible for manual bottle creation. |
| `Crosswire/Views/Setup/WelcomeView.swift` | M | Verify the dismissal path (`WelcomeView.swift:79-91`) lands on the new CTA empty state. No structural change needed if `ContentView` handles the empty state correctly. |

### No change needed

| Path | Reason |
|---|---|
| `CrosswireKit/Sources/CrosswireKit/Wine/Wine.swift` | `runProgram` at line 101 is the correct primitive; `BottleAutoProvision` calls it directly. |
| `CrosswireKit/Sources/CrosswireKit/Crosswire/Bottle.swift` | Model is correct as-is. |
| `CrosswireKit/Sources/CrosswireKit/Crosswire/BottleData.swift` | Path registration logic used unchanged by `BottleVM`. |
| `CrosswireKit/Sources/CrosswireKit/Crosswire/BottleSettings.swift` | Settings structure supports the new flow without modification. |
| `Crosswire/Extensions/Bottle+Extensions.swift` | `updateInstalledPrograms()` and `getStartMenuPrograms()` are called by `BottleAutoProvision` without modification. |
| `Crosswire/Views/CrosswireApp.swift` | Settings, Check for Updates, and Uninstall are already present. See Section 7. |
| `CrosswireKit/Sources/CrosswireKit/Engine/CrosswireEngine.swift` | Engine layer untouched by this redesign. |

---

## 6. Sequencing

### Chunk 0: Prerequisite (not a code commit)

**Name:** Diagnose and confirm `.exe` run flow
**What changes:** Nothing in the repo. Run the SWG installer in the current app, capture the failure mode, fix it.
**Dependencies:** None.
**Size:** Unknown. Non-negotiable gate before any other chunk.

### Chunk 1: Async bottle creation

**Name:** `BottleVM` async bottle creation
**What changes:** `Crosswire/View Models/BottleVM.swift` add `createNewBottleAsync` returning `Bottle` after `inFlight` clears. Existing synchronous path unchanged.
**Dependencies:** None (safe to build in parallel with Chunk 0 diagnosis work).
**Size:** S

### Chunk 2: `BottleAutoProvision` service

**Name:** Auto-provision service
**What changes:** New `CrosswireKit/Sources/CrosswireKit/Crosswire/BottleAutoProvision.swift`. Implements name generation, async bottle creation, before/after Program Files snapshot, `runProgram`, post-run program discovery, and pin registration.
**Dependencies:** Chunk 1.
**Size:** M

### Chunk 3: Empty-state CTA and `RunExeView`

**Name:** Exe-first empty state
**What changes:** New `Crosswire/Views/RunExeView.swift`. Modify `ContentView.swift:219-235` to replace the "Create Bottle" button with a "Run an .exe" CTA button.
**Dependencies:** Chunk 2.
**Size:** M

### Chunk 4: Fix `FileOpenView` zero-bottle path

**Name:** External open with no bottles
**What changes:** `FileOpenView.swift:62-64` call `BottleAutoProvision` instead of dismissing when bottles is empty.
**Dependencies:** Chunk 2.
**Size:** S

### Chunk 5: Window-focus behavior

**Name:** Minimize Crosswire on launch
**What changes:** `BottleView.swift:85-103`, `ProgramsView.swift:185-190`, `ProgramView.swift:80` add `NSApp.miniaturize(nil)` before each `Wine.runProgram` / `program.run()` call.
**Dependencies:** None. Independent of auto-provision work; can be built any time after Chunk 0 unblocks.
**Size:** S

### Chunk 6: De-emphasize manual bottle creation

**Name:** Move "Create Bottle" out of primary toolbar
**What changes:** `ContentView.swift:59-65` remove the `+` button from the primary toolbar or move it to the ellipsis menu. Add `File > New Bottle` menu item in `CrosswireApp.swift` commands. `BottleCreationView.swift` is not deleted.
**Dependencies:** Chunk 3 (the CTA must exist before the `+` is removed from primary position).
**Size:** S

### Chunk 7: Finder integration (future, separate task)

**Name:** "Open With Crosswire" for `.exe` files
**What changes:** `Info.plist` `CFBundleDocumentTypes` and `UTImportedTypeDeclarations`. `CrosswireApp.swift` `handlesExternalEvents` update. Scoped and built as its own task.
**Dependencies:** Chunk 3 confirmed stable.
**Size:** L

---

## 7. What's Already Done

The following items from the original "Missing entry points" list are already implemented as of v1.0.5/v1.0.6 and must not be rebuilt:

**Settings:** `ContentView.swift:86-89` has a `SettingsLink` inside the ellipsis menu (`...` button). `Crosswire/Views/Settings/SettingsView.swift` is complete with general toggles, default bottle path, and update preferences. The `Settings {}` scene is declared in `CrosswireApp.swift:134-136`.

**Check for Updates:** `ContentView.swift:90-93` has a "Check for Updates" button inside the ellipsis menu, gated by `updateChecker.canCheckForUpdates`, calling `updater.checkForUpdates()` via Sparkle. `CrosswireApp.swift:57-59` also includes a `SparkleView` under the application menu.

**Wiki / Website / GitHub:** All three links are present in the ellipsis menu (`ContentView.swift:95-113`) and duplicated in the Help menu (`CrosswireApp.swift:112-131`).

**Uninstall Crosswire:** `CrosswireApp.swift:63-67` adds an "Uninstall Crosswire..." menu item. `CrosswireApp.confirmUninstall()` presents a confirmation alert, and `performUninstall()` wipes the engine, all bottles, preferences, and logs, reveals the app bundle in Finder, and quits.

Nick's sequencing step "Add Settings and Check for Updates entry points" is already satisfied. This spec does not add new entry points for those features.

---

## 8. Risks and Unresolved Questions

**Bottle initialization timing.** `BottleVM.createNewBottle` returns a URL immediately but the bottle is not ready until `Wine.changeWinVersion` completes (`BottleVM.swift:52`), which can take 5-30 seconds. Calling `Wine.runProgram` before `inFlight` clears will run against an incomplete wineprefix. Chunk 1's async variant must resolve this cleanly; any race here will produce silent Wine failures that are difficult to diagnose.

**Progress communication.** There is currently no spinner visible to the user during the 5-30 second wineprefix initialization. `RunExeView` must show an indeterminate progress indicator for the entire span from "file picked" to "app window appears." Without it the user will assume Crosswire is frozen.

**Installer detection accuracy.** The before/after snapshot heuristic depends on installers writing to `drive_c/Program Files` or producing Start Menu `.lnk` entries. Some installers write only to `AppData` or other locations. Those apps will not be auto-discovered. The fallback of pinning the original `.exe` mitigates this but may produce a stale pin if the installer was a self-extracting archive. This is a known gap; no mitigation is proposed for v1 beyond documenting the behavior.

**Window focus race on Apple Silicon.** `NSApp.miniaturize(nil)` fires before the Wine process window is visible. The Wine process spawns via Rosetta, which has its own startup latency. On slower machines, the Windows app window may not appear for several seconds after Crosswire minimizes. Test this explicitly on M1 and M2 hardware. A short delay (e.g. 1 second) between process start and miniaturize may be necessary.

**`NSApp.miniaturize` vs `NSApp.hide`.** `miniaturize` sends the window to the Dock and keeps it accessible; `NSApp.hide(nil)` removes all windows. The observed annoyance is solved by either. Use `miniaturize` unless testing shows it does not consistently bring the Wine window forward, in which case `hide` is the fallback.

**Bottle naming collisions.** If the user runs `Setup.exe` twice, the provisioner creates `Setup` and `Setup 2`. This is functional but creates a confusing sidebar. Consider whether to warn the user ("A bottle named Setup already exists, create Setup 2?") or silently suffix. Decide before Chunk 2 is built.

**Concurrent provisioning.** If the user triggers "Run an .exe" while a provision is already in progress, `BottleAutoProvision` starts a second provisioning in parallel. The current `BottleVM` has no lock preventing this. `RunExeView` should disable itself while a provision is in flight, or `BottleAutoProvision` must queue requests.

**Manual bottle creation discoverability.** Moving the `+` button out of the primary toolbar (Chunk 6) may surprise power users. A `File > New Bottle` menu item must exist before the toolbar button is removed.
