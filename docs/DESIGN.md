# Swoop design system

The reference for how Swoop looks, moves and speaks, in both themes. It describes what ships today (values
come from the code; file pointers in each section). When you change a visual, change it here too.

- Visual pages (open in a browser): [`design/design-system.html`](design/design-system.html) and
  [`design/journeys.html`](design/journeys.html).
- Design folder index and rules: [`design/README.md`](design/README.md). Logo (app icon, menu bar glyph,
  construction, archive): [`design/brand/`](design/brand/README.md).
- Requirements and the original visual spec: the PRD (`docs/PRD.md`, kept locally) §1, §7–§12.
- Screenshots: [`images/`](images/) (`swoop-grid.png`, `swoop-search.png`, `swoop-list-compact.png`,
  `swoop-list-comfortable.png`).

---

## 1. Principles

1. **Speed over decoration.** The switcher appears instantly and is typeable on the first keystroke. Motion is
   short and never blocks input (PRD §9).
2. **Native first.** Real app icons, AppKit materials, SF Pro, SF Symbols, standard controls in Settings. Swoop
   should feel like part of macOS, not a web view.
3. **Restraint.** Dim by default, bright when selected. One accent at a time. No chrome that doesn't carry
   information.
4. **Frosted, never opaque, for floating UI.** Everything that floats over other apps (switcher, About, update
   window, onboarding, support card) is see-through: a behind-window blur, optionally tinted.
5. **One design line across surfaces.** A theme is applied to every surface it covers, with the same tokens.
   Never tune one surface by itself (e.g. a different tint for one window).
6. **Keyboard is primary, mouse works.** Selection never depends on hover.
7. **Private and honest copy.** Say what Swoop does and doesn't do (no tracking, no network without consent).

---

## 2. Themes

Settings → Appearance → **Theme**. Two built-in themes; **Swoop is the default** for new installs and for
anyone who never picked one (`AppSettings.theme`, default `.swoop`). A chosen theme is kept.

Theme is independent from **Appearance** (Follow System / Light / Dark): every surface works in both theme ×
appearance combinations.

| | **Swoop** (default) | **Classic** |
|---|---|---|
| Idea | The brand look: warm orange + violet glow over indigo (dark) or cream (light). | The original look: plain system blur, like a native HUD. |
| Floating surfaces | Behind-window blur **+ brand gradient at `Brand.frostTint` (55 %)**. Less see-through than Classic by design — the tint *is* the theme. | Behind-window blur only. Visibly see-through. |
| Accent | Brand orange (`Brand.orange`). | System accent color. |
| Settings window | Brand gradient behind the form (opaque window), transparent toolbar, orange switches, orange picker selection. | Standard macOS Settings window, untouched. |
| About | Custom About window (`AboutView`). | Standard macOS About panel, frosted (blur under its content). |
| Check for Updates | Custom update window (`UpdateWindowView`). | Standard `NSAlert`. |
| Support card | Brand surface, follows Light/Dark, orange coffee button. | Always dark HUD, yellow coffee button. |
| Onboarding | Brand (always). | Brand (always) — onboarding is the brand's first impression. |
| Switcher content | Identical: icons, highlight, search field, text tones. | Identical. |

**Rule:** the switcher's *content* (icons, rows, selection, search pill) is theme-agnostic. A theme changes
surfaces, accents and system-dialog replacements — not the information layout.

---

## 3. Tokens

All brand tokens live in `Swoop/UI/Theme/SwoopTheme.swift`. Prefer them over literals; add a token when a
value is shared by two or more surfaces.

### 3.1 Color

**Brand** (`enum Brand`)

| Token | Value | Use |
|---|---|---|
| `Brand.orange` | rgb(0.95, 0.42, 0.16) ≈ `#F26B29` | Primary accent: buttons, selection, links, switches, step dots, symbol badges. |
| `Brand.orangeLight` | rgb(1.00, 0.58, 0.24) ≈ `#FF943D` | Top stop of the prominent button gradient. |
| `Brand.violet` | rgb(0.45, 0.36, 0.95) ≈ `#735CF2` | Bottom-right glow of the brand background. |
| `Brand.frostTint` | `0.55` | Opacity of the brand gradient over the blur on every frosted Swoop surface. |

**Brand background** (`BrandBackground`): three layers.

| Layer | Dark | Light |
|---|---|---|
| Base wash (linear, top-leading → bottom-trailing) | `#211A36` → `#141226` (deep indigo) | `#FFF5ED` → `#F2E8FA` (cream → lilac) |
| Orange glow (radial, top-leading, radius 520 × scale) | `Brand.orange` @ 30 % | `Brand.orange` @ 28 % |
| Violet glow (radial, bottom-trailing, radius 560 × scale) | `Brand.violet` @ 40 % | `Brand.violet` @ 22 % |

`scale` = 1 for an ~800 pt surface. Use `FittedBrandBackground` for surfaces that resize (switcher, Settings);
it sets `scale = max(width, height) / 800`. Fixed small surfaces pass a scale (About/update 0.5, support card
0.65, picker thumbnail 0.17).

**Switcher text tones** (explicit, not vibrancy — matches the references):

| Role | Dark | Light |
|---|---|---|
| Name, selected / primary | white | black @ 88 % |
| Name, unselected (grid) | white @ 62 % | black @ 62 % |
| Subtitle (grid) | white @ 45 % (62 % selected) | black @ 45 % (60 % selected) |
| Secondary (list) | white @ 60 % | black @ 55 % |
| Placeholder | white @ 40 % | black @ 35 % |
| Empty-state hint | white @ 40 % | black @ 40 % |

**Fills and strokes** (switcher)

| Element | Dark | Light |
|---|---|---|
| Grid selection fill / stroke | white @ 11 % / white @ 10 %, 1 pt | black @ 8 % / white @ 35 %, 1 pt |
| List selection fill | white @ 13 % | black @ 7.8 % |
| List chip / ↩ keycap fill | white @ 8 % / 12 % | black @ 4.8 % / 7.2 % |
| Search pill fill / stroke | white @ 7.5 % / white @ 6 %, 0.5 pt | black @ 6 % / white @ 25 %, 0.5 pt |
| Panel border | white @ 14 %, 0.5 pt | white @ 14 %, 0.5 pt |
| Slim scroll bar track / thumb | white @ 6 % / 38 % | black @ 5 % / 30 % |

**Semantic colors**: green = granted / up to date; orange (system) = warnings and conflicts; red = not granted
and destructive; the badge red `#F53B36` is only for app badge counts (mirrors the Dock).

### 3.2 Materials

| Surface | Material |
|---|---|
| All frosted surfaces | `NSVisualEffectView`, `.behindWindow`, `.active`; **`.hudWindow` in dark, `.popover` in light** (`BehindWindowBlur`, `PanelBackgroundView`). |
| Swoop theme | the same blur + `BrandBackground` at `Brand.frostTint` (`FrostedBrandBackground`, or `FittedBrandBackground().opacity(Brand.frostTint)` on the switcher). |
| Windows hosting a frosted surface | `isOpaque = false`, `backgroundColor = .clear`. |
| Error HUD (`HUDController`) | `.hudWindow`, 14 pt corners, theme-independent. |

### 3.3 Typography

SF Pro (system font) everywhere; SF Pro Rounded only for keycaps and the shortcut recorder.

| Role | Size / weight |
|---|---|
| Onboarding step title | 30 bold |
| About app name | 24 bold |
| Shortcut recorder (onboarding) | 22 semibold rounded |
| Update window title | 17 bold |
| Onboarding subtitle | 14.5 regular, line spacing 2, max width 540 |
| List headline (comfortable) | 14 semibold |
| Support card title | 14 semibold |
| Search field | 13.8 medium (placeholder 13.8 regular) |
| Grid app name | 13.5 medium (**bold when selected**) |
| Brand button | 13.5 semibold (12.5 on the support card) |
| List app name (compact) / subtitle | 13 semibold / 13 regular |
| Keycap | 12.5 semibold rounded |
| Body (About, update, support card) | 12–12.5 regular |
| Grid subtitle / list caption | 12 regular |
| Footer links, small actions | 11–11.5 |
| List chips | 10.5 medium |

Search matches are emphasized in place: the matched range turns bold (regular → bold, semibold → heavy) and
primary color. In Settings, use the system text styles (`.headline`, `.callout`, `.footnote`).

### 3.4 Shape (corner radii)

Always `style: .continuous` (squircle) unless noted.

| Element | Radius |
|---|---|
| Switcher panel | 36 |
| Support card panel | 18 |
| Onboarding demo screenshots | 12–16 |
| Onboarding card / symbol badge | 14 / 16 |
| Choice card, link row | 12 |
| List row selection | 11 (comfortable), 9 (compact) |
| Picker tile | 9 |
| Link-row icon tile | 9 |
| Keycap | 6 |
| Grid selection highlight | 24 % of its side (icon + 20) |
| Buttons, search pill, chips | capsule |

### 3.5 Spacing and size

**Grid** (`SearchViewModel.metrics`; icon size Small 64 / Medium 80 / Large 96 pt)

| Metric | Value |
|---|---|
| Selection highlight | icon + 20 |
| Cell | width highlight + 10; height highlight + 8 + 17 (name) + 16 (subtitle) |
| Column / row spacing | max(4, icon × 0.1) / max(10, icon × 0.2) |
| Horizontal padding | 28 |
| Top (incl. search) / bottom | 75 (30 without search field) / 26 |
| Search pill | 242 × 29, centered; 21 above, 25 below |
| Min panel width | 400 |

**Lists** (`ListMetrics`)

| Metric | Compact | Comfortable |
|---|---|---|
| Panel width | 640 | 680 |
| Row height | 40 | 60 |
| Icon | 26 | 38 |
| Row content inset | 14 | 16 |
| Row gap | 4 | 4 |
| List inset from panel edge | 20 | 20 |
| Top (incl. search) / bottom | 73 (30 without) / 24 | same |

In lists the search pill spans from where the app icons start to where the scroll bar ends (24 above, 20
below). Lists draw their own 4 pt slim scroll bar (12 pt gap), never the system scroller.

Panels never exceed 90 % of the screen's visible frame; columns are whole cells (nothing clipped).
Max visible rows: grid 1–8, list 3–20 (Settings).

**Floating windows**: About 340 × 390; update window 340 × 290; onboarding 800 × 590 (50 top inset, 76 footer);
support card 360 wide, 16 padding.

### 3.6 Elevation

- Floating panels use the system window shadow (`hasShadow = true`); no custom shadow on the panel.
- Prominent brand button: orange glow shadow (35 %, r 8, y 3; soft in light: 16 %, r 4, y 2).
- `BrandIcon`: orange blurred square behind the app icon (45 %; 22 % soft in light) — never a shadow on the
  icon image itself (it would reveal the square bounds).
- Onboarding screenshots: black 22–30 % shadows to stack them like panels.

### 3.7 Motion

| Moment | Animation |
|---|---|
| Switcher open | Fade 0 → 1 in 0.24 s, cubic-bezier(0.2, 0.8, 0.3, 1). None with Reduce Motion. |
| Switcher close | Immediate (`orderOut`). |
| Support card in | Fade 0.25 s. |
| Onboarding step change | Spring (response 0.42, damping 0.88), slide 44 pt + fade, direction-aware. Reduce Motion: 0.15 s fade. |
| Step dots | Spring (0.35, 0.8); current dot widens 6 → 18. |
| Pickers, cards, status | ease-out 0.15–0.25 s. |
| Button press | opacity 0.82, scale 0.98, ease-out 0.12 s. |
| Symbol swaps | `.contentTransition(.symbolEffect(.replace))`. |

Always honor `accessibilityReduceMotion`.

---

## 4. Components

| Component | Where | Notes |
|---|---|---|
| **Switcher panel** | `SwoopPanelController`, `SwoopView` | Borderless `NSPanel`, `.popUpMenu` level, joins all Spaces, radius 36, 0.5 pt border. |
| **Search pill** | `SwoopView.SearchPill` | Capsule, magnifying glass, placeholder "Search windows…". One field for every layout; hidden (zero height) until typing when "Always show the search field" is off. |
| **Grid item** | `WindowGridItemView` | Icon in a selection square, name, subtitle; state symbol for minimized (`minus.square`) / full screen; badge capsule top-trailing; minimized icons at 75 %. |
| **List row** | `WindowListRow` | Compact: icon, app name (110 pt column), subtitle. Comfortable: icon, headline (project or title) + caption (app · detail). Up to two status chips (Minimized, Full screen, Tab, Other desktop); ↩ keycap on the selected row. |
| **Empty state** | `EmptyResultsView` | Title + hint, 64 pt area: "Finding windows…", "No windows", "No matching windows". |
| **Brand button** | `BrandButtonStyle` | Capsule. Prominent: orange gradient, white text, glow. Secondary: primary @ 12 % (dark) / 7 % (light) fill, 8 % stroke. Height 34 (30 in small windows). Keeps its color when the window isn't key. Pair with `.focusEffectDisabled()`. |
| **Brand icon** | `BrandIcon` | App icon with orange glow; `softInLight` for About/support card/update. |
| **Visual picker** | `VisualPicker` + thumbnails | Picture tiles 96 × 60 (drawn 128 × 80 at 75 %), 118 pt columns, accent border 2.5 pt when selected (`themeAccent`). Thumbnails are vector and follow light/dark. |
| **Themed switch** | `ThemedSwitchStyle` | Standard switch, orange tint in Swoop. |
| **Onboarding blocks** | `OnboardingView` | `StepHeader`, `SymbolBadge` (64 pt, color @ 14 %), `Card`, `ChoiceCard` (orange 2 pt border selected), `LinkRow`, `Keycap`, `StepDots`. |
| **Menu bar icon** | `MenuBarController.statusImage` | 18 pt vector template: the logo's swap arrows (round tail, tapered shaft, swept head) knocked out of a rounded square. With an update available: orange square, white arrows (not a template). Spec: `design/brand/README.md`. |

When a component is needed in a second place, move it to `Theme/` (or a shared file) rather than copying it.

---

## 5. Surfaces

### Switcher (both themes)
The product. Opens with the shortcut (default ⌥Tab) on the active display, centered (or where it was dragged,
per display, with "Draggable"). Three layouts (Settings → Appearance → Layout):

- **Grid** (default): wide panel, centered rows, incomplete last row centered.
- **List · Compact**: one-line rows; dense, scannable.
- **List · Comfortable**: two-line rows that lead with what tells windows apart (VS Code project or title).

Frosted in both themes; the Swoop theme adds the brand tint.

### Settings
Toolbar tabs: Keyboard, Appearance, Behavior, Permissions, Advanced (+ Debug in debug builds). Grouped forms,
no scroll bar in either theme. Swoop theme: brand background runs under a clear toolbar (macOS 26+ frosts
only content scrolled under it). Multiple-choice appearance settings use visual pickers, not menus.

### About / Check for Updates
Swoop: small frosted brand windows (icon, title, short copy, capsule buttons, orange links). Classic: the
standard About panel (frosted) and a standard alert.

### Support card
Floating card under the menu bar icon, top-right. First after 100 switches, or 2 days with at least 10
switches; then every 2 days after "Maybe later". Never again after helping or "Don't ask again". Ignored →
auto-hides as "Maybe later".

### Onboarding
800 × 590 frosted brand window, always brand-styled. Fixed content area so the footer never moves.

### Error HUD
Short non-activating bubble for safe activation failures, 3 s, lower part of the screen.

---

## 6. Journeys

### 6.1 First run
1. **Welcome** — brand icon, "Welcome to Swoop", promise in one line, stacked demo screenshots. *Skip setup*
   (goes straight to permissions if Accessibility is missing) or *Begin setup*.
2. **Permissions** — why Accessibility is needed, live status (updates by itself, no restart), *Grant
   Access*, *Open System Settings*, and an explicit "no Input Monitoring or Screen Recording" note. Can be
   skipped ("Skip for now").
3. **Shortcut** — big recorder, "Try it now" keycap, conflict warning, release behavior as two choice cards
   (Keep open / Switch on release), Launch at login and opt-in weekly update check (off by default).
4. **Look** — layout picker with a live demo screenshot, appearance segmented control. The window previews
   the choice.
5. **Support** — free and open source; coffee, GitHub star, report/suggest. Thank-you state after use.
6. **Done** — "You're all set", a cheat sheet of keys, primary *Swoop Away →* opens the switcher.

If Accessibility is revoked later, only the permissions step reopens.

### 6.2 Everyday switching
Press shortcut → panel fades in with the previous window selected (Smart order) → type to filter (matches
bold) → arrows / shortcut again to move → Return or click to switch → panel closes and the target is in
front, even on another desktop. Escape or click outside closes and returns to where you were.
*Switch on release* mode: hold the modifier, tap to move, release to switch (like ⌘Tab).

### 6.3 Customizing
Menu bar → Settings (⌘,). Changes apply live, including the theme on the open Settings window.

### 6.4 Updates
Opt-in only. Menu bar → Check for Updates shows the result (Swoop: update window that follows the check live;
Classic: alert). An available update tints the menu bar icon orange and adds a menu item.

### 6.5 Support
Card appears rarely, never interrupts typing, dismisses itself, remembers "Don't ask again".

---

## 7. Content and voice

- Short, plain, friendly. Second person. Lead with the benefit ("Every window, one keystroke.").
- Say what Swoop *doesn't* do when it builds trust ("Window information never leaves this Mac.").
- Title Case for buttons and menu items ("Open System Settings", "Check for Updates"); sentence case for
  labels, toggles and body copy.
- Use real key glyphs (⌥ ⌘ ⇧ ↩ ← →, esc) in keycaps.
- Ellipsis character `…` for in-progress states and placeholders.
- Product name capitalized "Swoop" in UI; lowercase `swoop` only where machines read it (bundle id, URLs).
- All UI text is localizable (`LocalizedStringKey` / `String(localized:)`); debug UI stays English.

---

## 8. Accessibility

- Every interactive element has a label; selected items add `.isSelected`. Grid items and list rows read as
  "App, title[, status]".
- Decorative images (`BrandIcon`, demo screenshots, symbol badges) are hidden from VoiceOver.
- Reduce Motion: no open fade, fade-only step transitions.
- Contrast: never rely on the tint for meaning; selection uses fill + stroke + weight.
- Keyboard: everything in the switcher and onboarding is reachable by keyboard; default actions bound to
  Return.

---

## 9. Rules (do and don't)

**Do**
- Use `Brand.*` tokens and `BrandBackground` / `FrostedBrandBackground` / `FittedBrandBackground`.
- Use `Brand.frostTint` for every frosted Swoop surface; change it in one place.
- Give every new floating surface both a Swoop and a Classic treatment, in light and dark.
- Use continuous corners and capsules; SF Symbols for glyphs; real app icons from `NSWorkspace`.
- Verify visuals over a varied backdrop. Capture the screen region (`screencapture -R`), not the window
  (`-l`), when checking translucency: window captures omit the blur of what's behind.

**Don't**
- Hard-code a tint or a brand color literal in a view.
- Make a floating surface opaque, or use a different tint per surface.
- Change switcher content (icons, rows, text tones) per theme.
- Use the system accent in Swoop-themed custom controls, or brand orange in Classic.
- Download or bundle app icons; add custom fonts.
- Use hover as the only selection signal.

---

## 10. Checklist for a new surface

1. Which themes? Floating → frosted in both; Swoop adds `FrostedBrandBackground`.
2. Window: non-opaque, clear background, opened with `BringToFront.show`.
3. Light and dark checked, in both themes.
4. Tokens only; new shared values added to `SwoopTheme.swift` and to this document.
5. Strings localizable; VoiceOver labels; Reduce Motion respected.
6. Screenshot comparison (Classic vs Swoop, light and dark) before merging.
