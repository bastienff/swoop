#!/usr/bin/env bash
# Build Swoop.app into ./build/ (Debug by default). Usage: scripts/build.sh [Debug|Release]
# Signing: uses the first "Apple Development" identity's team so the TCC (Accessibility)
# grant survives rebuilds. Override with SWOOP_TEAM=XXXXXXXXXX. Falls back to ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Debug}"
IDLINE="$(security find-identity -v -p codesigning 2>/dev/null | grep '"Apple Development:' | head -1 || true)"
HASH="${SWOOP_SIGN_IDENTITY:-$(echo "$IDLINE" | awk '{print $2}')}"
TEAM="${SWOOP_TEAM:-$(echo "$IDLINE" | sed -nE 's/.*\(([A-Z0-9]{10})\)".*/\1/p')}"
SIGN_ARGS=()
if [[ -n "$HASH" && -n "$TEAM" ]]; then
  SIGN_ARGS=(SWOOP_TEAM="$TEAM" CODE_SIGN_IDENTITY="$HASH")
else
  echo "warning: no Apple Development identity; ad-hoc signing (Accessibility grant resets on every rebuild)" >&2
  SIGN_ARGS=(CODE_SIGN_IDENTITY=- SWOOP_TEAM=)
fi
xcodebuild -project Swoop.xcodeproj -scheme Swoop -configuration "$CONFIG" \
  -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' \
  "${SIGN_ARGS[@]}" build -quiet
rm -rf build/Swoop.app
cp -R "build/DerivedData/Build/Products/$CONFIG/Swoop.app" build/Swoop.app
echo "Built build/Swoop.app ($CONFIG)"
