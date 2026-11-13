## What does this change?

<!-- One or two sentences. Link the issue it closes, e.g. "Closes #12". -->

## Why?

<!-- The problem it solves for people switching windows. -->

## How was it tested?

<!-- Commands you ran and what you checked by hand. For anything involving other desktops (Spaces),
     full-screen windows or native tabs: what you verified on a real desktop. -->

## Screenshots

<!-- For UI changes: before / after. Use demo windows, not your real window titles. -->

## Checklist

- [ ] `scripts/test.sh` passes
- [ ] `scripts/build.sh` builds, and I ran the app with `open build/Swoop.app`
- [ ] It stays in scope: it makes switching windows better (see "What Swoop won't do")
- [ ] No new permissions (Accessibility only) and no new dependencies
- [ ] Windows are never moved between desktops, and tabs are never pulled out of their group
- [ ] Testable logic lives in `Packages/SwoopCore`, with tests
- [ ] Docs updated if behavior changed (README, Settings text)
