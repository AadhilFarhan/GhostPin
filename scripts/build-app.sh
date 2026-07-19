#!/bin/bash
# Builds GhostPin.app into dist/ from the SwiftPM executable.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/GhostPin.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/GhostPin "$APP/Contents/MacOS/GhostPin"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# A stable local signing identity keeps the Screen Recording grant valid
# across rebuilds; anywhere it doesn't exist (CI, other machines) fall back
# to ad-hoc.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "GhostPin Dev"; then
  codesign --force --sign "GhostPin Dev" "$APP"
else
  codesign --force --sign - "$APP"
fi

echo "Built $APP"
