# Session briefs — 2026-05-28

Three sequential briefs. Execute in order. Each must land + validate before the next begins. Saved here as durable reference if the session context resets.

---

## BRIEF 1 — Foundation: race + auto-flow + naming bugs

Crosswire foundation pass. The auto-flow validation has been unreliable across multiple sessions because of an install-flow race condition (#94) that masks results from other auto-features. Fix the race first, then the dependent bugs, then validate cleanly on a fresh install.

Order matters. Do not parallelize. Do not start UI polish in this brief.

### 1. Bug #94 (install-flow race)
`Wine.runProgram` awaits the bottle's wineserver, which stays alive while installer-spawned launchers run. This blocks `JavaAppDetector.applyDefaultsIfNeeded` and `finalizeAppIdentity` from completing until the user manually closes the launcher. Per the wrap-up's analysis, fix one of two ways:

- Add an "await this specific installer PID" mode to runProgram so it returns when the installer process itself exits, regardless of child processes the installer spawned.
- Or run post-install code optimistically on installer's direct-exit, decoupled from wineserver lifecycle.

Pick the cleaner approach for the codebase and document why.

**Verify:** install SWG via the GUI without manually killing the launcher. `applyDefaultsIfNeeded` and `finalizeAppIdentity` must both complete before any user interaction with the launcher window.

### 2. Bug #95 (primary URL selection)
When no Start Menu shortcut exists, primary URL falls through to first-scanned .exe, which can be a runtime binary (`lib/jre/bin/javaw.exe` → bottle named "Java(TM) Platform SE 8"). Add a heuristic: prefer .exes in the bottle root or top-level Program Files subdirs over runtime/bundled paths (`lib/`, `jre/`, `runtime/`, `bin/` under a non-root folder). VERSIONINFO of the chosen URL is then more likely to produce a user-facing name.

**Verify** by re-running the case that produced "Java(TM) Platform SE 8" — should now resolve to the launcher's name.

### 3. Bug #98 (rename strips spaces)
Inline rename's `commitRename` path strips spaces. Find where, fix it. Small, visible.

**Verify** by renaming a library entry to "SWG Legends" with a space — should persist with the space.

### 4. MainActor deadlock guard
Per wrap-up's learning #4: starting a second Install while the first is hung freezes the app. Add an explicit "one install at a time" queue OR unhitch the install await from MainActor. Pick one approach, document why.

**Verify** by triggering two installs in close succession — second should queue or be rejected gracefully, app must not freeze.

### 5. Clean validation on fresh install
After 1-4 land, do this validation run end-to-end:

- Fresh bottle, install SWG via installer path. All three auto-flows fire (auto-name, plist auto-seed, dwrite=builtin) without manual intervention. No race. No deadlock. Launcher renders properly on first open.
- Fresh bottle, install Notepad++. Same expectation, also no false-positive on JavaApp detection paths.
- Report the validation table with each auto-flow's pass/fail state per install.

### Out of scope (Brief 1)
UI polish, color/theme changes, naming pass to user-facing strings, icon extraction, observability (#96), zip-aware install, Wine-side bugs (#93, #97, #99), bug #84.

Report what changed for each item. Report the validation table at the end. Stop after validation reports. Do not auto-chase if validation reveals a new layer — report and stop.

---

## BRIEF 2 — Visual polish + naming pass + icon extraction

**Send AFTER Brief 1 validates green.**

Foundation fixes (#94, #95, #98, MainActor) are shipped and validated with the validation table green. Proceed with the visual identity + naming pass.

The Crosswire app icon is the design source of truth. Blue gradient base, four-color tile accent system (yellow / green / red / blue), rounded-square aesthetic, macOS-native game-launcher feel. The current app does not reflect the icon at all — this brief makes them feel like the same product.

Reference apps for feel (not literal copies): Setapp (clean library), Mac App Store (rounded tiles, accent surfaces), Linear (depth, hover states, polish). Steam/Battle.net energy for the library model.

Read the frontend-design skill first.

Commit incrementally. Show me each major surface before the next. Order: **main window → settings sheet → per-entry gear sheet.** Polish is where unintended drift happens; reviewing per-surface prevents it.

### 1. Naming + vocabulary pass
Replace all user-facing "Bottle" terminology with the resolved naming model:

- Primary install button reads exactly: **"Install a Game or App"**
- The main collection is labeled **"Library"** (in header or sidebar)
- Individual entries display name + icon + metadata only — no noun. Skip "App"/"Program"/"Title" entirely on entries. The visual is sufficient.
- Per-entry sheet title is just the entry's name (not "Program Settings: X")
- Action buttons are verbs: **Run, Uninstall, Settings**
- Data path references: **"App Data"** if a noun is structurally required
- "Bottle" must not appear in any user-visible copy — audit window titles, alerts, settings labels, empty state, tooltips, ALL strings
- Internal `Bottle` Swift class stays unchanged. Don't rename the class, just relabel strings.
- Engine, Terminal, DLL Overrides, Windows Version, Wine version stay as-is in Advanced view (appropriate name leaks for power users)
- Single library. No game/app sections. No auto-classification. The user knows what their thing is; Crosswire doesn't try to categorize.

Report every string changed.

### 2. Color system
Replace dark-grey-on-dark-grey + orange with a real palette derived from the icon:

- **Primary background**: subtle gradient `#1a1d24` at top → `#13161c` at bottom. Depth without lightness.
- **Primary accent**: the icon's exact blue, sampled from the icon asset. Orange is gone — it fights with the icon.
- **Tile accents** (for monogram fallback): the four icon-tile colors (yellow ~#FFC93C, green ~#5DD46E, red ~#FF6B6B, blue ~#4A8FFF), deterministically cycled per entry so the same entry always gets the same color.
- **Surface elevation**: row `#1f232b`, hover `#262b34`, selected = blue-tinted ~10% opacity. Real depth, not flat-on-flat.
- All colors in a single `CrosswireTheme.swift` or `Colors.xcassets` color set. No hardcoded hex in views — one file is the source of truth.

Sample exact hex values from the icon asset, do not eyeball.

### 3. Library row layout
Taller (~64px). Icon on the left (real icon if extractable, monogram tile fallback — see section 5). Entry name 16pt SemiBold. Secondary line ("Last played 2h ago" / "Never launched") 12pt at 60% opacity. Run button (▶) prominent on the right, blue accent on hover. Gear icon smaller, secondary — the row's primary affordance is "click to run," gear is secondary. Hover: elevated surface color + 1.01x scale + 150ms ease transition.

### 4. Header / toolbar
"Crosswire" title 28-32pt SF Pro Display Bold. "Install a Game or App" button → blue, slightly taller, with a + icon. Primary CTA. Search field: soft surface fill, blue focus ring (not orange), placeholder "Search your library...". Move the version string (v1.x.x) out of the main window — relocate to Settings → About. Keep the settings gear icon top-right, slightly more prominent.

### 5. Icon extraction from installed apps
Currently colored monograms are the only visual identity per entry; they should be the fallback, not the default.

- Extract the actual app icon from the primary .exe's PE resource section. Swift libraries exist for this; alternatively Wine's Start Menu shortcut generation may have extracted the .ico to disk already in the prefix — check there first as a free shortcut.
- Fallback chain: extracted icon from .exe → Start Menu shortcut's .ico → colored monogram tile.
- Cache extracted icons per-entry. One-time work at identity-finalize time.
- Display at the same size and rounded-square treatment as monograms, so real icons and tile fallbacks coexist visually in the list without jarring size/shape differences.

Out of scope this brief: the bare-launcher / zip-install case (depends on a future feature).

### 6. Empty state
When no entries exist: Crosswire icon centered (large), headline **"Your Windows library, on Mac."**, subhead **"Drop a Windows .exe to install your first game or app."**, blue "Install a Game or App" button below. Tasteful, not childish. First-launch Setapp energy.

### 7. Settings sheet polish
Same gradient background and surface elevation as the main window. Group cards (General / Updates / About) get elevated surfaces, 10px rounded corners, proper internal padding. Blue toggles (not orange). Fix the duplicate "Automatically check for Crosswire updates" toggle — one toggle is presumably for app updates and one for engine updates but they share copy. Identify which is which, relabel correctly. Hide internal container paths from user view OR relabel as "App Data Location" with a Browse / Show in Finder button. About section: Crosswire icon small, "Crosswire 1.x.x" as primary line, "Engine 11.9.0" below, links to GitHub / website / "Report an issue".

### 8. Per-entry gear sheet
Same depth treatment. Hide "Bottle" terminology entirely (covered by section 1, just confirming for this surface). Default minimal view: entry name (editable inline with the rename-spaces bug now fixed from Brief 1), large Run and Uninstall buttons, "Advanced" disclosure below. Advanced reveals: prefix path, Windows version, DLL overrides, Engine version. Power-user stuff lives behind Advanced; default surface is for normal users.

**Preserve all current functionality.** Every button, action, and state that exists today must exist after. This is a visual + naming pass, not a model or behavior change.

### 9. Style the onboarding screens that Brief 3 builds

Brief 3 introduces a 5-screen first-launch onboarding (Welcome → Sentry consent → Notifications → Engine download → You're ready). Brief 2 owns the **visual** layer of those screens: same gradient background, same depth/elevation treatment, blue accent, distinctive Crosswire feel. Heading typography matches the main window's headline scale. Continue buttons are blue primary. Disclosure links ("What's included?") use the secondary text tone. Onboarding is the first impression — it must feel like the same product as the icon and the library window.

### Acceptance (Brief 2)
A first-time Mac user opens Crosswire and reads it as a polished, fun, Mac-native game-and-app launcher that belongs on their Mac. The app and the icon look like they're from the same product. Not generic. Not Wine-utility. Distinctively Crosswire.

Report what changed per surface. Stop after each major surface (main window, settings, per-entry gear) for review before proceeding to the next. Do not land the whole pass in one commit — polish review is per-surface.

---

## BRIEF 3 — Observability + close-out

**Send AFTER Brief 2 is shipped or in a defensible state.**

Visual polish pass is shipped or in current acceptable state. Wrap the session with the observability foundation the wrap-up doc flagged as needed, then close cleanly.

### 1. Bug #96 — Swift-side observability
Currently no structured Swift log, no crash bundle, no `hs_err` auto-pickup, no in-app log viewer. The bash-monitor pattern that's been used during debugging is doing what the app should do natively. Build it:

- Structured Swift-side log capturing app-level events (install start/complete, identity finalize, auto-flow firings, run/exit, crashes). Replaces the bash-monitor archaeology pattern.
- Crash bundle: on Wine crash, auto-collect any `hs_err_pid*.log`, the run log, bottle config, engine version, macOS version, and the structured Swift log into a single zip the user can view in-app.
- In-app log viewer: basic implementation in Settings → Diagnostics → "View logs" (or similar). Read-only, with a "copy to clipboard" and "open in Console" affordance.
- Wire into the existing failure-report dialog (#84-era feature) so when a user clicks "Report this issue," the crash bundle is included automatically.
- Privacy: no automatic upload, no telemetry. User explicitly chooses to share the bundle.

### 2. First-launch onboarding flow with consent and permissions

Build a guided onboarding shown exactly once per install (gated on a UserDefaults key). The flow:

- **Screen 1 — Welcome.** Crosswire icon, "Welcome to Crosswire," tagline "Run Windows games and apps on your Mac," Continue.
- **Screen 2 — Crash reporting consent.** Plain language: "Crosswire can send anonymous crash reports to help us fix bugs faster. No personal data is included." Buttons: "Help improve Crosswire" / "Maybe later." Disclosure link "What's included?" opens an inline panel listing exactly what Sentry receives (stack trace, app version, macOS version, Wine engine version, bottle config, scrubbed run log). Stores choice in UserDefaults; toggleable later in Settings → Privacy.
- **Screen 3 — Notifications.** "Get notified when downloads finish or apps update." [Allow] / [Not now]. Allow triggers `UNUserNotificationCenter.requestAuthorization`.
- **Screen 4 — Engine download.** "Crosswire needs to download its engine (~190MB) to run Windows apps." [Download Engine] (primary) / [Set up later] (secondary, defers but warns the user the app won't function until done). Triggers the existing engine-download path.
- **Screen 5 — You're ready.** "Drop a Windows installer to install your first game or app. The first time you do this, macOS may ask you to allow access to your Downloads folder and Terminal — this is normal." Single [Get Started] button.

**State management:**
- `hasCompletedOnboarding` boolean in UserDefaults
- Each individual permission state stored separately so we can detect "user revoked notifications in System Settings later" and re-prompt or grey out related features
- Settings → Privacy lists each permission with current state and either a toggle (for Sentry) or "Open System Settings" deep-link buttons (for OS-managed permissions like notifications)

**Do NOT ask for in onboarding:**
- Downloads or Terminal/AppleScript access — those are user-action-triggered system prompts; pre-asking is confusing. Screen 5 warns about them.
- Microphone, Camera, Photos, Contacts, Location, Calendar, Full Disk Access, Accessibility — Crosswire doesn't need any of these.

Visual styling of the onboarding screens is handled by Brief 2 (which adds a note to style screens this brief builds). Brief 3 owns the logic (Sentry SDK, UserDefaults plumbing, first-launch detection, gated-permission flow); Brief 2 adds the polish.

### 3. Session close-out
- Confirm everything is committed and pushed to main. Nothing uncommitted in working tree. Nothing local-only.
- Confirm CI is green on the latest commit.
- Update CLAUDE.md (or the project-state doc) with shipped fixes from Briefs 1-3 and remaining queue.
- List the top 3 things in the queue for the next session, with one-line context for each, in priority order. Likely candidates: #93 (patcher SEH crash, Wine-side), #97 (winhttp hang), zip-aware install, #84 (pre-existing SWG post-login crash). Pick the actual top 3 based on what's most leveraged.
- Stop. Stand down. Do not start anything new.

Summarize what went well with each brief, what was validated and tested, and what else you believe we need to focus on.
