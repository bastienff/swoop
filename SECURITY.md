# Security Policy

Swoop runs with the macOS **Accessibility** permission, which lets it read window titles of other apps and
bring windows forward. That's a trusted position, so security reports are taken seriously.

## Reporting a vulnerability

**Please don't open a public issue.** Report it privately on GitHub:
[Security → Report a vulnerability](https://github.com/bastienff/swoop/security/advisories/new).

Include what you found, how to reproduce it, and which Swoop and macOS versions you used. You'll get a reply
within a week, and a fix or a plan as soon as possible after that. Credit is given in the release notes
unless you'd rather stay anonymous.

## Supported versions

Only the latest release gets security fixes. Update with `brew upgrade --cask swoop`, or download it again
from [Releases](https://github.com/bastienff/swoop/releases/latest).

## What Swoop does and doesn't do

Useful context when assessing a report:

- **One permission:** Accessibility. Swoop never asks for Screen Recording or Input Monitoring.
- **No network:** Swoop has no network code. Nothing is sent anywhere.
- **Local data only:** recent-window history in `~/Library/Application Support/Swoop/`, and settings and
  remembered window ids in its preferences.
- **Private API:** one documented, optional use of non-public Accessibility functions to rebuild window
  handles after a restart (Settings → Behavior → *Remember windows on other desktops*). It reads; it
  never moves windows.
- **Release builds** are signed with a Developer ID and notarized by Apple. Only install Swoop from this
  repository's Releases or the `bastienff/tap` Homebrew tap.
