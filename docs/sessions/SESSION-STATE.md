# Session state — handoff at 2026-05-28 16:05 CDT

Snapshot of where Task D (the HIG-aligned visual redesign build pass) stands.
Source of truth for the design is `docs/specs/visual-design-direction.md`
(amended with the HIG fold-ins, commit `8a67081`).

Standing constraint: **native bones, custom skin** — use native mechanics
(toolbar, List, materials) while keeping the branded identity. No user-facing
strings mention Wine / engine / wrappers / version numbers.

## What's done (committed; all pushed to `origin/main`)

Task D runs as a sequence of small, surgical commits over the visual spec:

| # | Commit | What landed |
|---|--------|-------------|
| spec | `8a67081` | Six HIG amendments to `visual-design-direction.md` (native toolbar, native sidebar List, materials for overlays, SF Symbol metrics, a11y labels, metrics legend). |
| 1 | `cf35f24` | Project AccentColor orange → Crosswire blue (`0x418DF7`); inline Settings Done shortcut `.defaultAction` → `.cancelAction` (Esc dismisses; Return no longer intercepted by the sidebar List). |
| 2 | `08967c3` | Header restructure: custom header `HStack` replaced by the native unified toolbar (`.unifiedCompact`). Leading brand icon + chevron `Menu` (Settings / About / Check for Updates / Quit), inline "Crosswire" title, trailing primary-action group (sparkle / bell / gear placeholders + prominent blue "+" install). Tab control dropped. |
| 2-fix | `d6af693` | Toolbar brand icon: block-based Retina redraw + `.resizable().frame(18,18)` (fixes blur + the giant-icon bug). |
| 3 | `e937c13` | Library as a contained surface: region card `#1f232b`, 12pt radius, 1px `#262b34` hairline, small-caps `LIBRARY` header. Rows carry their own persistent surface (`#262b34` rest / `#2a2f38` hover). Branded hex, not material (persistent-shell rule). |
| 4 | `a86fa7e` | Library row redesign: circular play glyph + row gear removed, replaced by one discrete blue "Launch" pill; row-body click → detail. Right-click context menu (Launch / Show Details / Rename / Check Dependencies / Show in Finder / — / Uninstall…) with inline rename + dependencies sheet. |
| 2-fix | `3a24689` | Vertically center the toolbar brand icon: the Menu control seats its label ~1.75pt high and ignores SwiftUI offset/padding, so the nudge is baked into the bitmap. See the `do NOT "fix" to y:0` comment in `brandToolbarIcon`. |

All verified building clean (Debug) and runtime-checked against the real SWG
bottle. Theme tokens added in `CrosswireTheme`: `rowSurface`,
`rowSurfaceHover`, `regionBorder`, `Typography.sectionHeader`.

### Deliberate deviation to revisit
**"Change Icon…" is omitted from the row context menu.** There is no
icon-customization backing yet (deferred this session), and a no-op menu item
would mislead. The spec lists it — add it together with the storage + render
support, most naturally alongside the Commit 5 detail view.

## What's remaining

### Commit 5 — inline per-app detail + Settings sidebar → List + materials
- **Inline per-app detail.** Replace the `AppSettingsSheet` `.sheet(item:)`
  with an inline `.entryDetail(UUID)` route (the enum case already exists in
  `AppRoute`). Slide-in from the right, same pattern/animation as inline
  Settings. Back chevron + "Library" top-left. Content: large icon + editable
  name, category line, big blue Launch, secondary actions (Uninstall red /
  Check Dependencies / Show in Finder), Advanced disclosure (prefix path,
  Windows version, DLL overrides). This is the natural home for **Change Icon**
  (see deviation above) and the place to **rewire the row-body tap** from
  "open sheet" to `route = .entryDetail(bottle.id)`.
- **Settings sidebar → `List(selection:)`** (HIG fold-in). Rebuild
  `InlineSettingsView`'s hand-rolled `VStack` of buttons as a native
  `List(selection:)`. Inherits sidebar material + vibrancy, free keyboard nav
  (which is *why* Return was being intercepted — that was the native List
  doing its job), resize/AX for free. Overlay the 3pt blue left-edge accent bar
  on the selected row; drop the custom `surfaceSelected` background.
- **Materials on transient overlays** (HIG fold-in). Inline Settings + inline
  detail + popovers/menus use SwiftUI materials (`.regularMaterial`, or
  `.sidebar` for the Settings sidebar). The persistent library shell stays
  branded hex. Light mode is therefore NOT free — materials cover only the
  transient overlays.

### Commit 6 — atmospheric polish + single-instance (final stop)
- **Single-instance enforcement.** When Launch is clicked on an
  already-running program, bring the existing window to front instead of
  spawning a new process. Track by bottle UUID + primary exe path. Add an
  Advanced toggle "Allow multiple instances" defaulting off. (`Wine.runProgram`
  currently allows arbitrary duplicate launches.)
- **Atmospheric polish.** 150ms hover / 200ms slide-in consistency, monogram
  tile shadow, single surface-separation convention (1px border OR inner
  highlight, used everywhere).
- **Accessibility-label sweep** (HIG fold-in). Every symbol-only button
  (row Launch glyph, search, etc.) MUST carry an `.accessibilityLabel`. The
  toolbar buttons already have them; sweep the rest.
- **SF Symbol metrics** (HIG fold-in). Standardize toolbar/header symbols to
  13pt medium, monochrome at small sizes. Could be folded here or split into an
  optional Commit 7.

### Out of scope for this build pass
Notifications panel (bell is a placeholder), What's New panel (sparkle is a
placeholder), background-install rework, light mode, icon-extraction debug,
Sentry, the post-login SWG crash #84.

## To resume (fresh session runs Commit 5)
1. Read `docs/specs/visual-design-direction.md` (source of truth) — sections
   "Inline per-app detail view", "Inline Settings", "Materials vs branded hex".
2. Build Commit 5 as scoped above. Stop point after it: show the inline detail
   view AND the converted Settings sidebar.
3. Then Commit 6 (final stop).

## Repo state
- Branch: `main`
- HEAD: `3a24689` (+ this doc/comment housekeeping commit on top)
- Pushed: all Task D commits are on `origin/main`
- CI: confirm green on the pushed HEAD
- Working tree: clean after the housekeeping commit lands
