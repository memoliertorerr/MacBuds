#!/bin/bash
# Runs the macbuds CLI from inside a minimal .app bundle.
#
# Why: macOS aborts (SIGABRT, no output) any process that touches Bluetooth when
# the app "responsible" for it has no NSBluetoothAlwaysUsageDescription. A bare
# CLI inherits its launcher as the responsible app, so it only works from
# launchers that carry that key (Terminal.app does). Launching a bundle through
# LaunchServices makes the bundle itself responsible, so it gets its own prompt.
#
# Usage: scripts/macbuds-bundled.sh probe --channel 5
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --product macbuds >&2
APP=dist/macbuds-cli.app
mkdir -p "$APP/Contents/MacOS"
cp .build/debug/macbuds "$APP/Contents/MacOS/macbuds"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.memoli.macbuds.cli</string>
    <key>CFBundleName</key><string>macbuds</string>
    <key>CFBundleExecutable</key><string>macbuds</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSUIElement</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>macbuds talks to your Galaxy Buds to read their status and change their settings.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >&2

OUT=$(mktemp -t macbuds-out)
ERR=$(mktemp -t macbuds-err)
open -W -n --stdout "$OUT" --stderr "$ERR" "$APP" --args "$@" || true
cat "$OUT"
cat "$ERR" >&2
rm -f "$OUT" "$ERR"
