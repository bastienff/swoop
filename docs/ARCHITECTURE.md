# Swoop — Architecture

This document records **verified** platform behavior and the design decisions derived from it.
Every claim in §1 was exercised on a real desktop (macOS 27.0.1, Xcode 27, Apple Silicon, 5+ Spaces,
VS Code with `"window.nativeTabs": true`, `AppleWindowTabbingMode = always`) with the diagnostic
probe in `Swoop/Diagnostics/Probe.swift`. Re-run probes after macOS upgrades (see §9).

## Rules (do not regress)

These follow from the verified facts below. Changes that break one need new evidence first.

- **Public APIs only**, with one exception: remote-token element recovery (`_AXUIElementCreateWithRemoteToken`,
  `_AXUIElementRemoteTokenCreate`, `_AXUIElementGetWindow`), confined to `Platform/RemoteElements.swift`,
  resolved with `dlsym`, optional, with a public fallback (§2a). It only rebuilds handles; a recovered window
  is never focused without `RemoteRecoveryPolicy` classification (hidden tabs, F21). No CGS/SLS/SkyLight.
- **Never move a target window between Spaces**; never use `.moveToActiveSpace` on targets.
- **Never `AXPress` a Window-menu item for a possibly hidden native tab on another Space**: it relocates the
  tab group (F7). Use the two-step path (F9).
- **After cross-Space activation, confirm** the frontmost app and focused window, and re-assert (F10).
- **AX calls** set messaging timeouts, run enumeration off the main actor, and handle invalid elements.
- **No Input Monitoring or Screen Recording** permission requests (not needed, F13).
- **No network requests without consent.** The only one is the update check (`UpdateChecker`): an anonymous
  GET of GitHub's latest release, when the user clicks *Check for Updates* or daily/weekly/monthly if they enabled it (off by
  default). It only links to the release page (built from the version, not from the response); it never
  downloads or installs. A found update is shown quietly, never as a popup: the menu bar icon turns the logo's orange and the
  menu gets an orange "Swoop X Is Available" item at the top (plus the status in Settings and About).
- **Swift 6 strict concurrency**; `AXUIElement` crosses actors only via the `AXElement` wrapper.
- **Cross-Space and native-tab behavior** is claimed only when verified on a real desktop.

---

## 1. Verified platform facts (2026-11-12)

| # | Question | Result | Evidence (probe) |
|---|----------|--------|------------------|
| F1 | Does `kAXWindowsAttribute` list windows on other Spaces? | **No.** Only windows on the *current* Space, plus minimized windows. VS Code: 0 AX windows vs 16 CG windows. | `windows` |
| F2 | Do `kAXFocusedWindowAttribute` / `kAXMainWindowAttribute` work for an app whose windows are all on another Space? | **Yes.** Returns a live element (Slack, Notes, VS Code, Postman). | `windows`, `activate` |
| F3 | Is there a public, title-bearing list of *all* windows across Spaces? | **Yes, for AppKit-managed window lists:** Window-menu items whose `AXIdentifier == "makeKeyAndOrderFront:"`. Locale-independent. VS Code lists all 16 windows/native tabs; Finder, Postman, Slack, ChatGPT, Brave, Ghostty, 1Password, Activity Monitor too. Marks: `◆` minimized, `✓` key, `•` unsaved. **Not** present in DBeaver (SWT), Spark, OrbStack, Notes (custom menus). | `menus` |
| F4 | Does CG (`CGWindowListCopyWindowInfo`) give titles? | **No** without Screen Recording (`kCGWindowName` nil). It lists every window on every Space (ids, pid, bounds) but cannot distinguish a hidden native tab from an off-Space window (identical attributes). | `cgwindows`, `cgdetail` |
| F5 | How are native tabs exposed? | Only the selected tab's window appears in `AXWindows`. That window has an `AXTabGroup` child whose `AXRadioButton`/`AXTabButton` children carry each tab's exact window title; `AXValue == 1` marks the selected tab; supports `AXPress`. Readable only while the group is on the current Space. | `windows` |
| F6 | Window-menu `AXPress` + `activate()` on a **visible** window on another Space | **Navigates to that Space; window not moved.** Verified with Postman, Finder (two windows on two different Spaces), Ghostty. Space signature before/after = exact set of windows native to the destination Space. User visually confirmed. | `pressmenu` |
| F7 | Window-menu `AXPress` on a **hidden native tab** whose group is on another Space | **⚠ RELOCATES the whole tab group to the current Space.** Reproduced 3× with VS Code. **Forbidden path.** | `pressmenu` |
| F8 | `AXMain=true` + `AXRaise` + `NSRunningApplication.activate()` on an off-Space window element (F2) | **Navigates to its Space; window not moved.** (Slack, VS Code main window.) | `activate`, `twostep` |
| F9 | Two-step: F8 on the tab group's visible window, then `AXPress` the target `AXTabButton` locally | **Works.** Lands on the group's Space, switches tab in place; group not moved. | `twostep` |
| F10 | Focus after a Space switch | **Not guaranteed.** After navigating, macOS sometimes makes another app on the destination Space frontmost (Brave instead of Finder; Finder instead of Ghostty). Must confirm and re-assert focus after the Space change. | `pressmenu` |
| F11 | `com.apple.spaces` "Current Space" pref as a live signal | **Unreliable** (stale after switches). Not used. | — |
| F12 | Carbon `RegisterEventHotKey` for ⌥Tab on macOS 27 | Registers (`noErr`) and **fires** (synthetic HID-level event). Also accepts ⌥⇧Tab, ⌃⌥Tab, ⌘⌥Tab, bare Tab. No Input Monitoring or Accessibility needed for Carbon hotkeys. Confirmed with a physical keyboard. | `hotkey` |
| F13 | Permissions | Accessibility is required (AX). Input Monitoring: **not required** (no event tap). Screen Recording: **not required** (no titles from CG, no previews). | all |
| F15 | Can an off-Space tab group be read? | **Yes** through an element obtained off-Space (main/focused window or a learned anchor): its `AXTabGroup` children list every tab. All 16 VS Code projects were enumerated as precise `.tab` entries without visiting their Space. | app registry dump |
| F16 | Are Window-menu titles identical to AX window titles? | **Not always.** Brave truncates mid-title with `…` and drops the profile suffix; Activity Monitor uses different punctuation. Menu items are matched to elements by exact title first, then ellipsis/alphanumeric equivalence. | app registry dump |
| F17 | Activation from a background accessory app | macOS 14+ activation is cooperative. The panel activates Swoop when shown, then `NSApp.yieldActivation(to:)` + `activate()` on selection; `AXFrontmost` is a fallback. Verified with physical keyboard use. | app |
| F18 | Remote-token element ids (`_AXUIElementCreateWithRemoteToken`, private) | Token = `pid(4) 0(4) "coco"(4) id(8)`; `_AXUIElementRemoteTokenCreate` gives the token (and id) of any held element, locally. Ids are **small and dense** (VS Code after 1.5 h: all < 137; Finder/Ghostty < 101) and **stable** (same element → same id from any client). Sweep rate ≈ 70 000 ids/s for responsive apps. | `remotescan`, `tok` |
| F19 | Do ids outlive the client that obtained them? | **Yes.** Elements touched by a probe run (ids 75…100) were found by a later, separate process. So a relaunched Swoop can recover everything any earlier run (or any AX client) saw. | `remotescan` ×2 |
| F20 | Are never-requested windows reachable by id? | **No.** A window no client ever requested has no id: sweeping 1.7 M ids of VS Code found only the 2 of 16 windows previously seen. Recovery ≠ discovery of unvisited Spaces. | `remotescan` |
| F21 | What does a recovered *hidden native tab* look like? | A normal `AXStandardWindow` with **no tab bar**, `AXMain=0` (a VS Code window, value=0 in the main group). Indistinguishable from a standalone window by its own attributes → must be classified before use. | `elem` |
| F14 | TCC grant stability | Builds signed with a stable "Apple Development" identity keep the Accessibility grant across rebuilds. Ad-hoc builds lose it each rebuild. | build |

### Consequences
- There is **no public API to enumerate windows by Space or switch Spaces directly**. Space navigation
  is achieved only indirectly, by making a window on that Space main/key and activating its app (F6, F8).
- **One sanctioned private-SPI exception** (§2a): `_AXUIElementCreateWithRemoteToken`,
  `_AXUIElementRemoteTokenCreate`, `_AXUIElementGetWindow`, confined to `Platform/RemoteElements.swift`,
  resolved with `dlsym`, optional (Settings → Behavior), with automatic fallback to public-only behavior.
  Used only to *rebuild handles*; navigation still uses the public F8/F9 paths. `CGS*`/`SLS*`/SkyLight
  remain forbidden.

---

## 2. Window discovery design

`WindowDiscoveryService` produces `WindowSnapshot`s per running app (`activationPolicy == .regular`,
excluding our own pid). Per app, on a background queue, with `AXUIElementSetMessagingTimeout` (0.3 s):

1. **Visible windows** — `kAXWindowsAttribute`, keeping role `AXWindow` with subrole
   `AXStandardWindow` (incl. full-screen) or `AXDialog`; dropping untitled zero-size/system elements
   (e.g. Finder's desktop `AXScrollArea`). Gives a live element, title, minimized, full-screen.
2. **Native tabs** — for each visible window, its `AXTabGroup` → `AXTabButton` children. Non-selected
   tabs become `.tab` entries anchored to the group's visible window element.
3. **Window-menu entries** — items with identifier `makeKeyAndOrderFront:` (F3). Covers windows and
   tabs on other Spaces, with titles. `◆` ⇒ minimized.
4. **Main/focused window** — `kAXMainWindowAttribute`, `kAXFocusedWindowAttribute` (F2): a live element
   for an off-Space window even in apps without a window list (Notes, DBeaver, Spark).

Apps are discovered concurrently and each app's snapshot is applied as soon as it arrives
(`AsyncStream`), so a slow or still-launching app never blocks the rest of the grid; until the first
pass finds anything, the panel shows "Finding windows…" rather than "No windows".

**Merging** (`WindowRegistry`, pure logic in `SwoopCore.WindowMerger`): entries are keyed by
`(pid, title)` with multiplicity (Finder can have three "Downloads"). Precedence for each slot:
live visible element > tab of a known group > main/focused element > menu-only. A menu entry with no
other source is still listed (it is a real window), but marked as "menu-only" for activation.

**Learned anchors.** AX elements remain valid after their Space becomes inactive. Every refresh
(on `activeSpaceDidChangeNotification`, AX notifications, and panel open) records which titles live in
which visible window/tab group. These are kept until the element dies (`kAXErrorInvalidUIElement`) or
the app quits, so windows on previously visited Spaces get precise, safe activation.

### 2a. Recovering windows on other Spaces (private SPI, optional)

Problem: learned anchors (above) die with the Swoop process, so after a Swoop restart windows on
other Spaces became menu-only and, for tab-capable apps, unreachable until their Space was revisited.
Element ids live in the target app and survive (F18, F19), so `RemoteWindowRecovery` rebuilds them:

1. **Remember** — every pass records the ids of all held window elements (and windows announced by
   `kAXWindowCreated`, learned the moment they open) per app process (`pid@launchTime`), persisted in
   UserDefaults (`remoteWindowIDs.v1`, pruned when the process is gone).
2. **Gate** — recovery runs only for apps with unreachable windows: Window-menu titles no element/tab
   explains, or (no window list) more CG windows than reachable entries. Otherwise zero cost.
3. **Fast path** — recreate remembered ids (local), drop dead ones (`invalidUIElement`), keep
   selectable windows. After a relaunch this restores previously known windows with no sweep.
4. **Classify** (`SwoopCore.RemoteRecoveryPolicy`, F21) — a candidate with its own tab bar is used
   only if it is the group's selected tab (then its whole group is readable, F15). A candidate without a
   tab bar is used only if its title is not a known hidden tab **and** every other CG window with its
   exact frame is explained by known elements (a known group window explains all its tabs). Hidden tabs
   always share their group's frame, so such a window is provably standalone. Anything else is ignored.
5. **Sweep** — if windows are still unreachable, a background sweep on a utility queue checks ids
   `[cursor, highWater + 512)` (`highWater` = newest id seen, e.g. freshly vended menu items) in 8 ms
   slices with 24 ms pauses (scheduled, not slept: sweeps of several apps interleave on the queue), skipping descendants of known windows (one IPC each, no role read), capped
   at 400 k ids per app process. The cursor persists, so each id is checked once per app process; new
   ids later are covered incrementally. Findings trigger a single-app refresh.

Measured (2026-11-12, 16 apps): first-run sweeps 43–556 ids per app (9–526 ms wall at ≤ 25 % duty);
after a Swoop relaunch **no sweep at all**, recovered DBeaver window (other Space, no window list)
restored immediately as an anchor; idle CPU 0.0 %, RSS ≈ 70 MB.

**Exclusions:** own windows, non-regular apps, menu extras, tooltips/popovers (non-standard subroles),
windows without title *and* without a menu entry, transient system windows.

**Focus-steal protection** (verified 2026-11-13): while the switcher is open, apps can still take focus on
macOS 14+ when they launch, answer an AppleScript `activate`, or bring up their own window; plain
background `activate()` / `activate(ignoringOtherApps:)` requests are refused by macOS. On resign-key,
`FocusStealPolicy` reclaims unless a click outside happened (<0.5 s), a non-shift modifier other than the
switcher's own is held or was held <1 s ago (⌘Tab switches on ⌘ *release*; modifiers polled every 30 ms
while open, state only), the new frontmost app is system UI (SecurityAgent, Spotlight, loginwindow, Dock,
…), focus went to another Swoop window, or 2 reclaims already happened this opening. `NSApp.activate()` is
refused without fresh user input, so the reclaim falls back to setting `AXFrontmost` on Swoop's own app
element, off the main thread (Swoop services its own AX requests on main).

**Event-driven updates** (no polling): `NSWorkspace` didLaunch/didTerminate/didActivate/
activeSpaceDidChange; per-app `AXObserver` for `kAXWindowCreated`, `kAXUIElementDestroyed`,
`kAXTitleChanged`, `kAXFocusedWindowChanged`, `kAXMainWindowChanged`, `kAXWindowMiniaturized`,
`kAXWindowDeminiaturized`. Refreshes are debounced and coalesced per app (`RefreshScheduler`), also while
the switcher is hidden, so it opens up to date (opening still runs a full refresh as a safety net):
structure changes and activation → that app within ≤1 s; title changes → quiet 0.5 s, max 3 s, at most one
refresh per app every 3 s (terminal spinners retitle ~1/s). One-app refreshes reuse the app list from the
last full refresh (listing all apps' activation policy was ~65 % of a refresh) and, for title-only batches,
a ≤5 s-old `WindowCensus` (titles don't move windows, so the F7 hidden-tab check stays valid).
Measured (Release, 2026-11-13, with a terminal spinner): ~0.1–0.25 s CPU per minute; ~0 without one.

### Identity
`WindowID` = `pid` + source-specific key (AX element hash for live elements; `title#ordinal` for
tab/menu entries). Recent-usage persistence uses `bundleID + normalized title` (pids/elements don't
survive relaunch).

---

## 3. Activation design (`WindowActivationService`)

Hard rules (see Rules above): never move/re-space a target window, never use `.moveToActiveSpace` on targets,
never detach/merge tabs, never activate an unrelated window, fail safely instead.

Decision tree for target `T` of app `A`:

1. **T has a live visible-window element** (current Space or learned anchor):
   unminimize if needed → `AXMain = true` → `AXRaise` → `A.activate()` (F8).
2. **T is a tab in group G**:
   - G on current Space → `AXPress` T's tab button → step 1 on the resulting window.
   - G elsewhere → step 1 on G's visible window (navigate), then on arrival re-read the group on the
     current Space and press T's tab button (F9). If G's visible window is no longer the one we
     anchored, re-resolve on arrival; never press a menu item for T from another Space (F7).
3. **T is menu-only** (seen only in the Window menu):
   - Title equals `A`'s main window title → step 1 with the main window element.
   - App is **not tab-capable right now** (no tab group observed for A and no two of A's CG windows
     share identical bounds — hidden tabs always share their group's frame) → Window-menu `AXPress`
     + `activate()` (F6).
   - Otherwise → `A.activate()` (navigates to A's main window Space without moving anything), then
     look for T on the arrived Space and select it locally; if not found → **safe failure**
     (brief HUD: "Couldn't reach ‘T’ without moving it — open its desktop once").
4. **Focus confirmation** (F10): after any step, wait for `didActivateApplication`/
   `activeSpaceDidChange` (≤ 700 ms). If `frontmostApplication != A` or A's focused window ≠ T,
   re-apply step 1 on T's now-local element (max 2 retries).
5. **Stale entries**: before acting, verify the pid is alive and the element answers `kAXRoleAttribute`;
   otherwise refresh A and re-resolve by `(title, ordinal)`; if gone → no action + HUD. Never fall
   back to "any window of A".

---

## 4. Global shortcut (`GlobalShortcutManager`)

- Carbon `RegisterEventHotKey` / `InstallEventHandler` (F12). Default **⌥Tab**. No Input Monitoring.
- Re-registered dynamically when settings change; old registration is removed first.
- Pressing the shortcut while the switcher is open toggles it closed. While the panel is key, Tab /
  ⇧Tab also move selection (handled locally, not globally).
- **Bare Tab** is opt-in (Settings → Keyboard), with a warning: it swallows Tab system-wide while
  enabled. Same Carbon mechanism; still no Input Monitoring.
- Conflict detection: `eventHotKeyExistsErr` from Carbon (another app owns it) + a table of
  well-known system shortcuts (⌘Tab, ⌘Space, ⌃Space, ⌘`, …) + enabled entries in
  `com.apple.symbolichotkeys` where readable.

---

## 5. Swoop panel (`SwoopPanelController`)

- `NSPanel` subclass, `.nonactivatingPanel` + `.borderless`, `canBecomeKey = true`, level
  `.popUpMenu`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient,
  .ignoresCycle]` (applies only to *our* panel). Being non-activating, the previously active app
  stays active, so dismissing without selection leaves focus where it was.
- Content: SwiftUI (`SwoopView` → search pill + `WindowGridView`) in an `NSHostingView` over an
  `NSVisualEffectView` (`.hudWindow`, `.behindWindow`, rounded ~28 pt, hairline border, shadow).
- Keyboard: local `NSEvent` monitor while key (arrows, Return, Escape, Tab); typing goes to the
  search field, which is focused on open.
- Dismissal: Escape, toggle shortcut, `resignKey`, and a global left/right-mouse-down monitor
  (mouse global monitors need no extra permission) for outside clicks.
- Sizing: computed by `SwoopCore.GridLayout` from result count, icon size, and the target
  screen's `visibleFrame`; max width ≈ 90 % of screen, fixed max rows, scroll beyond. Shown on the
  active display (screen with key window/mouse, configurable).
- Swoop's own windows left open behind other apps (Settings, About, …) would come forward when the panel
  activates Swoop: they're ordered out while it's open and put back at their exact z-position afterwards
  (above the CG window that was below them), without activating Swoop.
- Shows cached registry immediately; a refresh runs in the background and the grid updates in place
  (selection preserved by `WindowID`).

## 6. Search (`SwoopCore.WindowSearchEngine`)

Case/diacritic-insensitive. Fields: app name, window title, VS Code project, tab title. Score tiers:
exact > prefix (field or word) > contiguous substring > fuzzy subsequence (gap/word-boundary
weighted). VS Code project matches get a small bonus (never enough to jump a tier). Ties → recency.
Empty query → MRU order.

## 7. VS Code adapter (`VSCodeProjectAdapter`)

Bundle IDs: `com.microsoft.VSCode`, `com.microsoft.VSCodeInsiders` (also `com.vscodium` if present).
Title grammar (default `window.title`): `[dirty ]activeEditor — rootName[ (Workspace)]` with em-dash
separator; a title without separator is the root name. Project = last ` — ` component, `(Workspace)`
stripped. Display: project prominently, file secondary. Native tabs come from F5/F3 like any app;
editor tabs inside VS Code are never enumerated (not exposed as windows).

## 8. Modules and concurrency

```
Packages/SwoopCore   (pure Swift, no AppKit; `swift test`)
  WindowEntry, WindowMerger, WindowSearchEngine, GridLayout/GridNavigator, RecentUsage, Shortcut,
  VSCodeTitleParser
Swoop (app target)
  App/        main, AppDelegate, AppController (composition root) + WorkspaceObserver, WindowControllers
  Platform/   AXElement (Sendable wrapper), WindowDiscoveryService, WindowActivationService,
              AXObserverHub, PermissionManager, GlobalShortcutManager, UpdateChecker (opt-in, §Rules)
  Registry/   WindowRegistry (@MainActor, @Observable), RecentWindowsStore, AppSettings
  UI/         SwoopPanelController, SwoopView (+ WindowGridView, WindowGridItemView),
              SearchViewModel, MenuBarController (+ LaunchAtLogin), HUDController, OnboardingView,
              Settings/ (SettingsView, ShortcutRecorder)
  Diagnostics/Probe (research probes), DebugCommands (DEBUG only)
```
Space awareness is folded into `WorkspaceObserver` (`activeSpaceDidChangeNotification` → refresh →
learned anchors); there is no separate Space service because no public Space API exists.

- UI, registry, panel: `@MainActor`. AX enumeration: `nonisolated` functions on a concurrent
  background queue, one task per app, each bounded by AX messaging timeouts; results (Sendable
  snapshots + `@unchecked Sendable` `AXElement` wrapper around the immutable CF reference) are
  merged on the main actor.
- Activation runs on the main actor (short AX calls with timeouts; needs ordering with
  `NSRunningApplication`).
- No third-party dependencies.

## 9. Diagnostics

**DEBUG builds** also listen for `Tools/swctl` commands (distributed notification
`com.bastienff.swoop.debug`): `show`, `hide`, `type <q>`, `key left|right|up|down|return|escape`,
`hotkey` (posts the configured shortcut as a real HID event), `post <keyCode> <mods>`,
`setshortcut <keyCode> <mods>`, `dump <file>`, `diagnostics <file>` (the diagnostics report), `snapshot <png>`, `snapwin <png> <title>`,
`appearance system|light|dark`, `refresh`, `settings`, `checkupdates` / `menucheckupdates` (button / menu
path), `updatemock off|newVersion|upToDate|offline`, `autoupdates on|off`, `autocheck5` (automatic check in 5 s), `openmenu [cmdcomma]` (menu bar menu; optionally presses ⌘, in it), `scrollsettings <y>`, `demo` (fixed generic windows for README
images; pauses discovery), `snapshot <png> clear` (content only, transparent, @2x). Build with
`swiftc -O Tools/swctl.swift -o build/swctl`. Used to verify behavior end-to-end; on-screen
Space membership is checked with CG on-screen window signatures (no Screen Recording needed).

**Settings → Debug** (DEBUG builds only; not compiled into Release): build/permission/registry/recovery
state, plus actions — reset Accessibility via `tccutil` and relaunch/quit (first-install test), show/reset
onboarding, system prompt, forget anchors (simulates a relaunch for recovery tests), forget remembered
windows, refresh, open registry dump, update check response (real / mock new version / mock up to date /
mock offline) + forget update state + run the automatic check in 5 s, demo windows on/off, show switcher/test HUD, clear recents, reveal
data folder, reset all settings, relaunch, quit.

**Diagnostics report** (all builds; menu → Report a Problem, or Settings → Advanced; `DiagnosticsReport`,
`DiagnosticsInfo`, `SessionStats`): plain text, no window titles unless opted in. Sections: install (path,
translocation, signature kind/team, other copies, Homebrew, login item), status (Accessibility, shortcut
and key code, keyboard layout, Secure Keyboard Entry and its owner, element recovery, Swoop CPU/memory),
this session (shortcut presses, opens, switch outcomes with route and duration, apps that took focus from the
open switcher), macOS settings that change switching (switch-to-desktop-on-activate, rearrange desktops,
separate desktops per display, Stage Manager, tabbing mode, reduce motion/transparency), known
switchers/window managers/remappers running (fixed process-name list), Swoop settings, displays, per-app
discovery (AX responsiveness and errors, timing, observer, windows here vs in the window server, Window
menu, tab groups, anchors, listed entries by source), apps with windows Swoop doesn't list, the window
list, and this session's log (switch outcomes and focus steals are logged without titles).

### Probes

DEBUG builds only (`Probe.swift` and its launch hook are not compiled into Release).
`open build/Swoop.app --args --probe <cmd> <outfile> [args]` with `cmd` ∈ `windows [bundleFilter]`,
`menus [bundleFilter]`, `pressmenu <pid> <title[@n]|~substr> <press+activate>`,
`activate <pid> <cgWindowID|0> <main+raise+activate…>`, `twostep <pid> <tabTitle>`, `tour <seconds>`,
`hotkey`, `remotescan <bundleFilter> <seconds> [maxId]` (id layout + timed sweep, F18–F20),
`elem <bundleFilter> <id>` (describe one element recovered by id, F21), `attrs <bundleFilter>`
(attributes of Window-menu items and tab buttons). Launch through `open` so TCC attributes the process to the app. Settings → Advanced also
exposes a registry dump.

## 10. Known limitations

- Windows that **no AX client has ever requested** (opened before Swoop first ran, on Spaces not
  visited since) have no element id (F20): only their main/focused window and Window-menu entry are
  known. For tab-capable apps a safe failure is shown rather than moving windows. Keeping Swoop
  running (launch at login) avoids this: windows are learned as they are created.
- Recovery depends on private SPI (§2a); if a macOS update removes it, Swoop falls back to the
  public behavior (windows on other Spaces reachable after revisiting them once per Swoop run).
- Duplicate titles within one app (e.g. several Finder "Downloads") are distinguished only when their
  elements were seen; menu-only duplicates are activated through their own menu item (F6) only when
  the app is not tab-capable.
- No Space numbers/names are shown (no public API).
- Unminimizing a minimized window lets macOS decide where it reappears (system behavior).
- Multi-display placement is implemented (active window / cursor / primary display) but has only been
  exercised on a single display.
- Window titles that change constantly (spinners) are matched by element identity for focus
  confirmation; leading status glyphs are ignored for recency.
