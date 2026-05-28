# Crosswire Visual Design Direction

## Reference

Battle.net launcher (macOS) is the reference for structural and atmospheric 
patterns. Not a literal clone — the energy, not the details.

## Principles

1. The app's identity lives in chrome (icon + tabs + header), not in 
   wordmark headlines.
2. Every UI region is a contained surface with its own elevation, padding, 
   and chrome.
3. Depth via subtle elevation, not heavy decoration.
4. Background work surfaces through notifications, not blocking dialogs.

## Header / chrome

**HIG alignment (2026-05-28):** use the native macOS toolbar (`.toolbar`)
with `.unifiedCompact` style rather than a custom header `HStack`. This gives
free chrome behavior (customization, compact-on-narrow, traffic-light
coordination, fullscreen hide) and a proper inline window title at the leading
edge. Drop the tab control — tabs inside a toolbar are not a native pattern,
and Library is the only section. Reintroduce navigation (TabView or sidebar)
only when a second section exists.

- Leading toolbar item (`.placement(.navigation)`): Crosswire icon ~28pt with
  a `chevron.down`; click opens a `Menu` (Settings, About, Check for Updates,
  Quit). No "Crosswire" wordmark text.
- Inline window title: the Crosswire mark sits at the leading edge next to the
  traffic lights via the unified title bar — the title bar is no longer empty
  chrome, but it carries the icon/mark, not app-name text.
- Trailing toolbar items (`.placement(.primaryAction)`, in order): sparkle
  (What's New, future), bell (Notifications, future), gear (Settings, wired),
  and the "+" install affordance (prominent blue tint — Apple's primary-CTA
  pattern). The "+" moves here from inside the library container.
- No tab control. Library is implicit.

## Library page

- Library is a contained surface: background #1f232b (one step lighter 
  than page #1a1d24), rounded 12px corners, subtle 1px border at #262b34 
  OR inset 0 1px 0 #262b34 inner highlight (pick consistently).
- Section header "Library" inside the container top-left, 11pt SemiBold 
  uppercase tracking, 60% opacity.
- "+" install button top-right inside the container (Battle.net favorites-
  bar pattern). When library is empty, the empty-state CTA is the primary 
  "Install a Game or App" button.
- Each row is its own surface at #262b34, rounded 8px.
- Row hover: surface lifts to #2a2f38, 1.01x scale, 150ms ease.
- Row selected: blue-tinted background at ~10% opacity.

## Library row structure

- Left: monogram tile (4-color cycle) OR extracted icon, ~48pt rounded 
  square.
- Center: entry name 16pt SemiBold + metadata line 12pt regular 60% opacity 
  ("Last played 2h ago" / "Never launched").
- Right: discrete "Launch" button — blue background, white ▶ icon + 
  "Launch" text, rounded 6px, padding, hover state.
- No gear icon on the row.

## Row interactions

- Single-click row → navigates to inline per-app detail view.
- Click Launch button → runs program (subject to single-instance check).
- Right-click / two-finger click row → contextMenu:
  - Launch
  - Show Details
  - Rename
  - Change Icon...
  - Check Dependencies
  - Show in Finder
  - --- (separator)
  - Uninstall... (red, destructive)

## Inline Settings

- Opens within main window (no new window chrome, no separate traffic 
  lights). Slide-in from right, 200ms ease.
- Layout: left sidebar nav (General / Updates / Privacy / About / Advanced), 
  right content pane.
- **HIG alignment (2026-05-28):** build the sidebar with native
  `List(selection:)` rather than a hand-rolled `VStack` of buttons. This
  inherits native sidebar material + vibrancy, free keyboard navigation
  (which also resolves the Return-key interception issue — that was the
  native List doing its job), and resize/AX for free. Overlay our 3pt blue
  left-edge accent bar on the selected row for brand continuity; drop the
  custom `surfaceSelected` background and let the system render selection.
- Footer: version chip bottom-left (muted text), Done button bottom-right 
  (blue primary).
- Updates section: TWO toggles — "Automatically check for Crosswire app 
  updates" and "Automatically check for Engine updates". Each binds to its 
  own UserDefaults key (do not collapse to one).
- General section: "App Data Location" with Show in Finder button (not 
  raw container path).
- About section: small Crosswire icon, app version, engine version, links 
  to GitHub / Crosswire website / "Report an Issue".

## Inline per-app detail view

- Opens within main window, slide-in from right (same pattern as Settings).
- Replaces the existing detached per-app settings window entirely.
- Back chevron + "Library" top-left.
- Content: large app icon + name (editable inline), category line, big 
  blue Launch button, secondary actions (Uninstall in red, Check 
  Dependencies, Show in Finder), Advanced disclosure (prefix path, 
  Windows version, DLL overrides, engine version).

## Colors

All in centralized `CrosswireTheme.swift` AND `Assets.xcassets/AccentColor`. 
No hardcoded hex in views.

- Page background: gradient #1a1d24 (top) → #13161c (bottom)
- Region surface: #1f232b
- Row surface: #262b34
- Row hover: #2a2f38
- Row selected: accent blue at ~10% opacity
- Primary accent: Crosswire blue, sampled from app icon, used everywhere
- Project AccentColor in Assets.xcassets: SAME Crosswire blue (NOT orange)
- Tile fallback colors: 4 colors from icon (yellow, green, red, blue)
- Text primary: #FFFFFF
- Text secondary: #FFFFFF at 60% opacity
- Text muted: #FFFFFF at 40% opacity

### Materials vs branded hex (HIG alignment, 2026-05-28)

Hybrid rule — native bones, custom skin:

- **Transient overlays** (inline Settings, inline per-app detail, popovers,
  dropdowns/menus) use SwiftUI materials (`.regularMaterial`, or the native
  `.sidebar` material for the Settings sidebar). They sit OVER the library;
  the blur reads as "a panel on top of the app" and auto-adapts to light/dark
  and desktop tint.
- **Persistent library shell** (page gradient, region surface #1f232b, row
  surfaces #262b34/#2a2f38) stays branded hex. This is the opaque
  game-launcher shell (Battle.net reference leans opaque, not blurred);
  full-material here would dilute the identity into generic-Finder.
- Light mode is therefore NOT free: materials cover only the transient
  overlays. The persistent shell still needs a parallel light palette in
  `CrosswireTheme` for the future light-mode pass.

## Typography

- Tab labels: 14pt SemiBold
- Section headers: 11pt SemiBold uppercase tracking, 60% opacity
- Row name: 16pt SemiBold
- Row metadata: 12pt Regular, 60% opacity
- Button labels: 14pt Medium
- Body: 14pt Regular

## Atmospheric details

- Hover transitions: 150ms ease
- Slide-in transitions: 200ms ease from right
- Monogram tile shadow: 1px y-offset, 4px blur, 8% black
- Surface separation via 1px borders or 1px inner highlight (pick one, 
  use everywhere)
- No gratuitous animation
- **HIG alignment (2026-05-28):** every symbol-only button (header gear /
  bell / sparkle / "+", row Launch glyph, search, etc.) MUST carry an
  `.accessibilityLabel`. Non-negotiable.

## SF Symbol metrics (HIG alignment, 2026-05-28)

- Toolbar/header symbols: 13pt, medium weight, large symbol scale (native
  `.toolbar` auto-configures these once adopted; match manually elsewhere).
- Monochrome rendering at small sizes for clarity; hierarchical only for
  subtle larger-size emphasis. Match symbol weight to adjacent text weight.
- New symbols: `bell` (Notifications), `sparkles` (What's New),
  `chevron.down` (icon dropdown indicator) — all 13pt medium.

## Metrics legend — intentional HIG divergences (2026-05-28)

These are deliberate launcher-density choices. Do NOT "HIG-correct" them:

- Library row height ~64pt (HIG content list is 32–44pt).
- Row name 16pt SemiBold (HIG body/headline is 13pt).
- Button labels 14pt Medium (HIG is 13pt).

Everything else should track HIG: standardize one-off spacings to an 8pt
rhythm, image-only buttons ≥24×24, window content margins ≥20pt, toolbar
symbols 13pt/medium per above.

## Single-instance enforcement

- When user clicks Launch on a program that's already running, bring the 
  existing window to front instead of spawning a new process.
- Track by bottle UUID + primary exe path.
- Add Advanced toggle "Allow multiple instances" defaulting off.

## Future panels (designed for, NOT in current build pass)

### Notifications panel
Bell icon top-right opens anchored dropdown. Event types:
- Install started / progress / complete / failed
- Engine update available / installed
- App crashed (with View Details / Report actions)
- Dependencies installed
- App ready to launch

Empty state: "You're all caught up!" with sleeping bell icon.
Notifications persist across restarts until dismissed (UserDefaults).

### What's New panel
Sparkle icon top-right opens anchored dropdown. Crosswire-curated content:
- Crosswire release notes
- Engine update changelog
- Tips for known-good Windows apps

### Background installs
Click Install → sheet for picker → dismisses immediately after start →
install runs in background → notification shows progress → notification 
on completion ("[App] is ready to launch") or failure.

Replaces current foreground-blocking install pattern. Architectural change 
touching ContentView+Install.swift, Wine.swift, new Notifications.swift, 
new NotificationsView.swift.

## Out of scope for the current build pass

- Notifications panel implementation (just the bell icon placeholder)
- What's New panel implementation (just the sparkle icon placeholder)
- Background install rework
- Light mode (separate session)
- Icon extraction debug (diagnose-only this session)
- Sentry crash reporting integration
- The post-login SWG crash #84
