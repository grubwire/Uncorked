# Session state — Task D complete (2026-05-29)

Task D (the HIG-aligned visual redesign build pass) is **done and pushed to
`origin/main`**. Design source of truth: `docs/specs/visual-design-direction.md`.

Standing constraint: **native bones, custom skin** — native mechanics
(toolbar, List, materials) with the branded identity. No user-facing strings
mention Wine / engine / wrappers / version numbers.

## What shipped (all on `origin/main`)

| # | Commit | What landed |
|---|--------|-------------|
| spec | `8a67081` | Six HIG amendments to the design spec (native toolbar, native sidebar List, materials for overlays, SF Symbol metrics, a11y labels, metrics legend). |
| 1 | `cf35f24` | AccentColor orange → Crosswire blue (`0x418DF7`); inline Settings Done shortcut → `.cancelAction`. |
| 2 | `08967c3` | Native unified toolbar (`.unifiedCompact`) replaces the custom header HStack: leading brand icon + chevron Menu, inline "Crosswire" title, trailing sparkle/bell/gear placeholders + install button. Tab control dropped. |
| 2-fix | `d6af693` | Toolbar brand icon: block-based Retina redraw + `.resizable().frame(18,18)`. |
| 2-fix | `3a24689` | Brand icon vertically centered by baking a 1.75pt downward shift into the bitmap (the toolbar Menu control seats labels high and ignores SwiftUI offset/padding — there's a `do NOT "fix" to y:0` comment guarding it). |
| 3 | `e937c13` | Library as a contained surface (`#1f232b`, 12pt radius, 1px `#262b34` hairline, small-caps `LIBRARY` header); rows get their own surface (`#262b34` rest / `#2a2f38` hover). Branded hex, not material. |
| 4 | `a86fa7e` | Row redesign: circular play + row gear removed → one discrete blue "Launch" pill; row tap → detail. Right-click context menu (Launch / Show Details / Rename / Check Dependencies / Show in Finder / — / Uninstall…). |
| 5 | `5ee41dd` | Inline per-app detail via `.entryDetail(URL)` (replaces the `AppSettingsSheet` sheet); Settings sidebar → native `List(selection:)` (fixed an `id: \.self` selection bug); materials (`.regularMaterial`) on the transient Settings + detail overlays. |
| 5-fix | `0ad8662` | Dropped the 3pt sidebar accent bar — the native `.sidebar` selection is already an on-brand blue pill. |
| 6 | `fc0768b` | Single-instance launch enforcement + "Allow multiple instances" per-bottle setting (default off); a11y sweep (hid decorative search glyph, labeled the field). |
| 6-refine | `7f567c9` | Install affordance: labeled "+ Install" toolbar button (not a bare "+"), suppressed on the empty state. Spec metrics-legend note added. |

All verified building clean (Debug) and runtime-checked against the real SWG
bottle. Theme tokens added: `rowSurface`, `rowSurfaceHover`, `regionBorder`,
`Typography.sectionHeader`.

## Decisions worth remembering

- **Install affordance.** Toolbar button is labeled **"+ Install"** (blue
  primary, `.labelStyle(.titleAndIcon)`), **suppressed when the library is
  empty** (`if !bottleVM.bottles.isEmpty`) so the centered hero
  "Install a Game or App" button is the single CTA there. Full wording stays
  on the hero only. This is intentional — see the spec's metrics legend; do
  not native-correct it back to a bare icon.
- **Sidebar selection** is the native `.sidebar` blue pill (no custom accent
  bar / background) — on-brand because AccentColor is Crosswire blue.
- **Single-instance** is per-bottle: liveness via `Wine.runningProcessIDs`
  (`ps -E` matched on `WINEPREFIX`), focuses the existing window
  (`NSRunningApplication`, `.regular` policy) instead of spawning. Self-heals
  (only suppresses the spawn when a focusable window exists), so it can't get
  stuck. **Not runtime-verified** — needs the SWG GUI launched twice, which
  was avoided (heavy launcher + known post-login crash #84). Worth a manual
  double-Launch check.
- **Deliberately omitted:** "Change Icon…" (no icon-customization backing),
  DLL-overrides editor (none exists), engine version in the detail Advanced
  (CLAUDE.md's no-engine-strings rule overrides the spec line). Don't ship
  empty editors.

## Dead code — future cleanup pass (do NOT remove piecemeal now)

These are unmounted/unused but still compiled, kept for reference (matching
the project's prior pattern):

- `Crosswire/Views/AppSettingsSheet.swift` — replaced by `EntryDetailView`;
  only a doc-comment reference remains.
- `Crosswire/Views/Settings/SettingsView.swift` — replaced by
  `InlineSettingsView` back in the inline-navigation pass.

A single cleanup commit should delete both files and drop their pbxproj
entries (via the `xcodeproj` gem).

## CLAUDE.md

No stale UI references — CLAUDE.md is engine/infra-focused and only mentions
`EngineSetupView` (the engine-download flow), which is unchanged. No update
needed for the header/install restructure.

## Next-session queue (priority order)

1. **Dead-code cleanup** — delete `AppSettingsSheet.swift` +
   `SettingsView.swift`, drop pbxproj entries, build green. Small, low-risk.
2. **Runtime-verify single-instance** — once the SWG (or any GUI app) launches
   reliably, confirm a second Launch focuses the existing window and that
   "Allow multiple instances" lets it spawn. Adjust the `NSRunningApplication`
   matching if winemac.drv apps don't surface as `.regular`.
3. **Settings content cleanup (was "Section 3")** — relabel the two update
   toggles, App Data Location "Show in Finder", rebuild the About card
   (icon + version + links). `InlineSettingsView` group wrappers are still
   thin behavior-preserving shims.
4. **Light mode** — the persistent shell needs a parallel light palette in
   `CrosswireTheme` (materials already adapt; branded hex does not).
5. **Out of scope (designed-for, not built):** Notifications panel (bell
   placeholder), What's New panel (sparkle placeholder), background-install
   rework, icon extraction, Sentry, SWG crash #84.

## Repo state
- Branch: `main`; HEAD `7f567c9`; all Task D commits pushed.
- CI: green on `7f567c9` (SwiftLint / Build / CodeQL).
- Working tree clean.
