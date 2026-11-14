#!/usr/bin/env bash
# Package Swoop.app into a drag-to-Applications disk image.
# Usage: scripts/make_dmg.sh [path/to/Swoop.app] [out.dmg]     (defaults: build/Swoop.app, build/Swoop.dmg)
#
# Uses dmgbuild (Python), which writes the Finder layout (.DS_Store) itself: no Finder scripting, so it also
# works on CI. It is installed into build/.dmg-venv on first use. The window background is
# packaging/dmg/background.tiff; regenerate it with packaging/dmg/background.swift after changing the layout.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Swoop.app}"
OUT="${2:-build/Swoop.dmg}"
[[ -d "$APP" ]] || { echo "error: $APP not found (run scripts/build.sh first)" >&2; exit 1; }

VENV=build/.dmg-venv
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet "dmgbuild==1.6.7"
fi

# The volume's name is what Finder shows in the window title.
rm -f "$OUT"
"$VENV/bin/dmgbuild" -s packaging/dmg/settings.py -D app="$APP" -D background=packaging/dmg/background.tiff "Swoop" "$OUT"
echo "Built $OUT"
