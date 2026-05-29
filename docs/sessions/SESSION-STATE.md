# Session state — redesign loop finished (2026-05-29)

The HIG-aligned visual redesign (Task D) shipped, and this session closed out
three of the four follow-up items. Design source of truth:
`docs/specs/visual-design-direction.md`.

Standing constraint: **native bones, custom skin**. No user-facing strings
mention Wine / engine / wrappers / version numbers (CLAUDE.md naming rule —
overrides spec lines that mention "engine version").

## Shipped (all on `origin/main`)

**Task D — redesign (prior session):** spec amendments `8a67081`; accent
`cf35f24`; native toolbar `08967c3` (+ icon fixes `d6af693`, `3a24689`);
contained library + rows `e937c13`; row redesign + context menu `a86fa7e`;
inline detail + native Settings sidebar + materials `5ee41dd` (+ accent-bar
drop `0ad8662`); single-instance + a11y `fc0768b`; labeled "+ Install"
affordance `7f567c9`; Task-D doc `4006c3f`.

**This session (redesign-loop cleanup):**
- `1c8d18e` — **dead-code removed**: deleted `AppSettingsSheet.swift` +
  `SettingsView.swift` and their pbxproj entries (superseded by
  `EntryDetailView` / `InlineSettingsView`). Build green.
- `c2f67e5` — **Settings content cleanup**: real General (App Data Location
  with Show in Finder + Change…, no raw container path), Updates (second
  toggle relabeled "Windows compatibility updates" — no "engine" string,
  still its own key), About (icon + version + GitHub / Website / Report-an-
  Issue links; dropped the engine-version line). Replaced the thin shim
  group-views with finished content.

Theme tokens: `rowSurface`, `rowSurfaceHover`, `regionBorder`,
`Typography.sectionHeader`. All built clean and runtime-checked.

## Decisions worth remembering
- **Install affordance**: labeled "+ Install" toolbar button (blue primary,
  `.titleAndIcon`), suppressed when the library is empty (hero CTA is the
  single target there). Intentional — don't native-correct to a bare icon.
- **Sidebar selection**: native `.sidebar` blue pill, no custom accent bar.
- **No user-facing engine/version strings** anywhere (Updates toggle, About,
  detail Advanced all comply). NOTE: `DiagnosticsView` still has a
  `Section("Engine")` — diagnostics is developer-facing but worth a sweep.
- **Omitted on purpose**: "Change Icon…" (no backing), DLL-overrides editor
  (none exists), engine version in detail/About. Don't ship empty editors.

## ⚠️ High-priority bug found this session (own diagnosis next)

**Launch re-runs the installer.** Clicking Launch on the SWG bottle ran
`Z:\Users\nick\Downloads\SWGLegendsSetup.exe` (the setup wizard) rather than
the installed launcher — i.e. the bottle's **primary-program resolution
picked the installer over the installed app**. Launch re-running setup is a
broken core action and is a bigger deal than single-instance. #95 territory
(primary-program heuristic). Confirmed 2026-05-29 on bottle
`BD247FEE-…` (its `appDisplayName` is "Star Wars Galaxies Legends" but the
primary URL points at the Downloads installer). Needs a focused session:
trace `pickUserFacingPrimary` / `finalizeAppIdentity` / how the install flow
sets `primaryProgramURL`, and why it kept the source installer.

## Single-instance — needs its own pass

Shipped (`fc0768b`) but **currently inert** (safe). Verified at runtime:
`Wine.runningProcessIDs` matches `WINEPREFIX=<prefix>` in `ps -E`, but macOS
**hides the environment of Crosswire's detached `wine start /unix` processes**
from `ps` (`ps -E -p <pid>` shows command only). So detection returns empty →
the guard never fires → it always falls through and spawns. The self-healing
design means launches are NOT broken, just un-deduped.

- **Lead fix candidate: match by argv, not env.** The wine process's argv IS
  visible (`Z:\…\X.exe` / `C:\Program Files…\X.exe`) even when env isn't. Map
  the bottle's program URL → its Windows path/basename and match.
- **Weak spot that approach must solve:** basename collisions across bottles
  (two bottles with the same exe name). Needs to disambiguate (e.g. full
  Windows path, or correlate with the launched program), not just basename.
- Confirming winemac.drv GUI apps surface as `NSRunningApplication` with
  `.regular` policy is still unverified (the installer, not a GUI app, was
  what launched during the test — see the bug above).

## Next-session queue (priority order)
1. **Launch-runs-installer bug** (above) — high priority, broken core action.
2. **Single-instance pass** — argv-matching, solve basename collisions, verify
   `.regular` policy + focus end-to-end.
3. **Light mode** — parallel light palette in `CrosswireTheme` for the
   persistent branded-hex shell (materials already adapt; hex doesn't).
4. Minor: sweep `DiagnosticsView`'s `Section("Engine")` wording.

## Out of scope (designed-for, not built)
Notifications panel (bell placeholder), What's New panel (sparkle
placeholder), background-install rework, icon extraction, Sentry.

## Open issues
- **#84 / #93** — SWG launcher JavaFX crashes (login click; mid-Update). Engine
  (Wine-fork) level, not app code — need CrossOver patch diff or newer Gcenx
  Wine. (#90 and #92 closed this cycle.)

## Repo state
- Branch `main`; HEAD `c2f67e5`; all pushed.
- CI: confirm green on the latest commit.
- Working tree clean.
