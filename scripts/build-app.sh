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
codesign --force --sign - "$APP"

echo "Built $APP"
