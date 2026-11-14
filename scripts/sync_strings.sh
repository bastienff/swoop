#!/bin/sh
# Update Swoop/Localizable.xcstrings with the app's current UI strings (what Xcode does on build in the IDE).
# Usage: scripts/sync_strings.sh   (builds Debug first; Debug-only and diagnostics files are left out)
set -eu
cd "$(dirname "$0")/.."

scripts/build.sh Debug >/dev/null
DATA="build/DerivedData/Build/Intermediates.noindex/Swoop.build/Debug/Swoop.build/Objects-normal/arm64"
[ -d "$DATA" ] || { echo "No .stringsdata in $DATA" >&2; exit 1; }

# Debug pane, swctl commands, probes and diagnostics stay English: keep them out of the catalog.
set --
for f in "$DATA"/*.stringsdata; do
    case "$(basename "$f" .stringsdata)" in
        Debug*|Probe|DiagnosticsReport) ;;
        *) set -- "$@" --stringsdata "$f" ;;
    esac
done

xcrun xcstringstool sync Swoop/Localizable.xcstrings "$@"
echo "Synced Swoop/Localizable.xcstrings ($(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["strings"]))' Swoop/Localizable.xcstrings) strings)"
