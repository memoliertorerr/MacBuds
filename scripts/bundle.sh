#!/bin/bash
# Builds MacBudsApp in release mode and wraps it in dist/MacBuds.app.
#
# The bundle is what lets macOS show the Bluetooth permission prompt: a bare SwiftPM
# executable has no Info.plist, so it is denied (or killed) without one.
#
# Usage: scripts/bundle.sh [--open | --install]
#   --open     launch dist/MacBuds.app after building
#   --install  copy it to /Applications (replacing an older copy) and launch that one
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product MacBudsApp
BIN="$(swift build -c release --show-bin-path)/MacBudsApp"
VERSION="$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/BudsProtocol/BudsProtocol.swift)"

APP=dist/MacBuds.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/MacBuds"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.memoli.macbuds</string>
    <key>CFBundleName</key><string>MacBuds</string>
    <key>CFBundleDisplayName</key><string>MacBuds</string>
    <key>CFBundleExecutable</key><string>MacBuds</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>MacBuds talks to your Galaxy Buds to show their battery and change their settings.</string>
</dict>
</plist>
PLIST
# Sign with a real identity when one exists. macOS ties the Bluetooth permission to the
# app's signature; an ad-hoc signature changes with every build, and the permission can then
# silently stop applying (the app sees the earbuds as "not paired"). A named identity keeps
# it stable across rebuilds. Override with MACBUDS_SIGN_IDENTITY, or set it to "-" for ad-hoc.
IDENTITY="${MACBUDS_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    # By hash, since a keychain can hold several certificates with the same name.
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/"Apple Development:/ { print $2; exit }')"
    IDENTITY="${IDENTITY:--}"
fi
codesign --force --sign "$IDENTITY" "$APP"
if [[ "$IDENTITY" == "-" ]]; then
    echo "Built $APP (ad-hoc signed)"
else
    echo "Built $APP (signed with a development certificate)"
fi

case "${1:-}" in
    --open)
        open "$APP"
        ;;
    --install)
        DEST=/Applications/MacBuds.app
        if [[ -e "$DEST" ]]; then
            read -r -p "Replace $DEST? [y/N] " answer
            [[ "$answer" == [yY]* ]] || { echo "Left $DEST as it was."; exit 0; }
            osascript -e 'quit app id "dev.memoli.macbuds"' 2>/dev/null || true
            rm -rf "$DEST"
        fi
        cp -R "$APP" "$DEST"
        echo "Installed $DEST"
        open "$DEST"
        ;;
esac
