#!/bin/bash
set -euo pipefail

# Build the MacRelay iOS app for simulator and launch it.
# Requires Xcode with iOS 17+ simulator runtime installed.
#
# Usage:
#   ./scripts/build-ios.sh

PRODUCT="MacRelayiOS"
SDK="iphonesimulator"
DEST="platform=iOS Simulator,name=iPhone 16"

echo "==> Building $PRODUCT for $SDK"
swift build --product "$PRODUCT" -c debug --sdk "$SDK" --triple arm64-apple-ios17.0-simulator

APP_BUNDLE=".build/debug/${PRODUCT}.app"
BIN=".build/debug/$PRODUCT"

if [ -f "$BIN" ]; then
    echo "==> Creating .app bundle"
    mkdir -p "$APP_BUNDLE"
    cp "$BIN" "$APP_BUNDLE/$PRODUCT"

    cat > "$APP_BUNDLE/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MacRelayiOS</string>
    <key>CFBundleIdentifier</key>
    <string>com.macrelay.ios</string>
    <key>CFBundleName</key>
    <string>MacRelay</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>UILaunchStoryboardName</key>
    <string>LaunchScreen</string>
    <key>UIRequiredDeviceCapabilities</key>
    <array><string>arm64</string></array>
    <key>UISupportedInterfaceOrientations</key>
    <array><string>UIInterfaceOrientationPortrait</string></array>
</dict>
</plist>
EOF

    echo "==> Launching in simulator"
    xcrun simctl boot "$DEST" 2>/dev/null || true
    open -a Simulator
    xcrun simctl install booted "$APP_BUNDLE"
    xcrun simctl launch booted com.macrelay.ios
else
    echo "ERROR: Binary not found at $BIN"
    echo "SwiftPM executable targets produce CLI binaries, not .app bundles."
    echo "For a full iOS app experience, open this package in Xcode:"
    echo "  open Package.swift"
    echo "Then select the MacRelayiOS scheme and an iOS simulator destination."
    exit 1
fi
