# Contributing to Swoop

Thanks for helping! Swoop is small on purpose, so the best contributions make **switching windows**
faster or more reliable. Bug fixes, especially for apps or desktop setups Swoop gets wrong, are the most
valuable thing you can send.

## Before you start

- **Bugs:** open an issue with the bug form. Say which app's window misbehaved and how your desktops are set
  up (Spaces, full screen, native tabs).
- **Features:** open a feature request first, so we can agree it fits before you write code. Out of scope:
  window previews, tiling or snapping, managing desktops, browser tabs, plugins, themes. See
  [What Swoop won't do](README.md#what-swoop-wont-do).
- **Small fixes** (typos, obvious bugs): just send a pull request.

## Set up

Requires an Apple silicon Mac with macOS 14+ and Xcode 16+. No other dependencies.

```sh
git clone https://github.com/bastienff/swoop.git
cd swoop
scripts/test.sh              # unit tests (Packages/SwoopCore)
scripts/build.sh             # Debug build → build/Swoop.app
open build/Swoop.app         # always launch with `open`, so macOS gives the permission to the app
```

`scripts/build.sh` signs with your first *Apple Development* certificate if you have one, so the
Accessibility permission survives rebuilds. Without one it signs ad hoc, and macOS asks for the permission
again after every build: grant it, or remove the old entry in System Settings → Privacy & Security →
Accessibility.

Debug builds add **Settings → Debug** and a **Debug** menu in the menu bar: reset the permission, show the
onboarding, load demo windows, simulate a relaunch, and more.

## How the code is organized

- `Packages/SwoopCore/`: pure Swift with no AppKit: search, grid and list layout, window merging, recent
  order, the support card schedule. **Anything that can be tested goes here, with tests** (Swift Testing).
- `Swoop/`: the app: Accessibility, window discovery and activation, hotkey, UI.
  New files are picked up automatically (folder-synchronized Xcode project).

## Naming

- **Swoop** (capitalized) is the product name: use it in sentences, UI text, docs and release titles.
- **swoop** (lowercase) is for anything machines read: the bundle id `com.bastienff.swoop`, log subsystem,
  identifiers and labels (`com.bastienff.swoop.<thing>`), the repo and URLs, the Homebrew cask `swoop`.
- In Swift, follow Swift conventions: types and modules are capitalized (`SwoopCore`, `SwoopView`).

## Rules that keep Swoop trustworthy

These come from behavior verified on real desktops. Please don't break them:

1. **Never move a window to another desktop**, and never pull a native tab out of its group. Swoop goes to
   the window; the window doesn't come to you.
2. **One permission:** Accessibility. No Screen Recording, no Input Monitoring, no network, no analytics.
3. **Public macOS APIs only**, with one documented, optional exception for recovering window handles after a
   restart (`Swoop/Platform/RemoteElements.swift`). Don't add more private API.
4. **Swift 6 strict concurrency.** Accessibility calls run off the main thread with timeouts.
5. **Stay light:** no polling, no work while the switcher is closed, no new dependencies.

If a change touches other desktops (Spaces), full-screen windows or native tabs, **test it on a real
desktop** and describe what you checked in the pull request. Automated tests can't cover that part.

## Pull requests

- Keep them focused: one fix or feature per pull request.
- Fill in the checklist in the template. `scripts/test.sh` must pass; the PR check runs it plus a build.
- For UI changes, add before/after screenshots. Use demo windows (Debug → Load Demo Windows), never your
  real window titles.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages and PR titles, in
  the imperative: `fix: keep focus after switching to a full-screen window`. Release notes are generated
  from them: `feat` → New, `fix` → Fixes, `perf` → Performance, `type!:` → Breaking changes; `refactor`,
  `test`, `ci`, `docs`, `build` and `chore` count as internal. Write the subject for users ("what changed
  for me?") and explain the why in the body.

By contributing you agree your work is released under the [MIT License](LICENSE), and that you'll follow
the [Code of Conduct](CODE_OF_CONDUCT.md).
