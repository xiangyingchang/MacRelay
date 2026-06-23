#!/bin/bash
set -euo pipefail

# Build the MacRelay iOS app for simulator and launch it.
# Requires Xcode with iOS 17+ simulator runtime installed.
#
# Usage:
#   ./scripts/build-ios.sh

PRODUCT="MacRelayiOS"
SDK="iphonesimulator"
TRIPLE="x86_64-apple-ios17.0-simulator"
DEVICE_NAME="iPhone 17"
DEST="platform=iOS Simulator,name=$DEVICE_NAME"

# Check SDK availability
echo "==> Checking SDK: $SDK"
if ! xcrun --sdk "$SDK" --show-sdk-path &>/dev/null; then
    echo "ERROR: iOS simulator SDK ($SDK) not found."
    echo "Download it in Xcode → Settings → Platforms → iOS Simulator."
    exit 1
fi

# Check simulator runtime
echo "==> Checking simulator: $DEVICE_NAME"
if ! xcrun simctl list devices available "$DEVICE_NAME" | grep -q "$DEVICE_NAME"; then
    echo "==> Creating simulator device: $DEVICE_NAME"
    RUNTIME=$(xcrun simctl list runtimes ios | grep -v "^==" | head -1 | awk '{print $NF}')
    if [ -z "$RUNTIME" ]; then
        echo "ERROR: No iOS simulator runtime found."
        echo "Download one in Xcode → Settings → Platforms."
        exit 1
    fi
    xcrun simctl create "$DEVICE_NAME" "$DEVICE_NAME" "$RUNTIME" || {
        echo "ERROR: Could not create simulator '$DEVICE_NAME'."
        echo "Available devices:"
        xcrun simctl list devices available | head -20
        exit 1
    }
fi

echo "==> Building $PRODUCT for $SDK ($TRIPLE)"
SDK_PATH=$(xcrun --sdk "$SDK" --show-sdk-path)
swift build --product "$PRODUCT" -c debug --sdk "$SDK_PATH" --triple "$TRIPLE"

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
    <key>MinimumOSVersion</key>
    <string>17.0</string>
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
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.macrelay.ios</string>
            <key>CFBundleURLSchemes</key>
            <array><string>macrelay</string></array>
        </dict>
    </array>
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
    echo "For a full iOS app experience, open this package in Xcode:"
    echo "  open Package.swift"
    echo "Then select the MacRelayiOS scheme and an iOS simulator destination."
    exit 1
fi
