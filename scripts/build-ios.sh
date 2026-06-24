#!/bin/bash
set -euo pipefail

# Build the MacRelay iOS app for simulator and launch it.
# Requires Xcode with iOS 17+ simulator runtime installed.
#
# For real device deployment, open Package.swift in Xcode,
# select the MacRelayiOS scheme, choose your Personal Team,
# and Run (⌘R).
#
# Usage:
#   ./scripts/build-ios.sh

PRODUCT="MacRelayiOS"
SDK="iphonesimulator"
TRIPLE="x86_64-apple-ios17.0-simulator"
DEVICE_NAME="iPhone 17"
DEST="platform=iOS Simulator,name=$DEVICE_NAME"
BUNDLE_ID="com.xiangyingchang.macrelay"

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
    cp "Sources/${PRODUCT}/Info.plist" "$APP_BUNDLE/Info.plist"

    echo "==> Ad-hoc codesigning for simulator"
    codesign -s - --entitlements - "$APP_BUNDLE" <<< '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>' 2>/dev/null || true

    echo "==> Launching in simulator"
    xcrun simctl boot "$DEST" 2>/dev/null || true
    open -a Simulator
    xcrun simctl install booted "$APP_BUNDLE"
    xcrun simctl launch booted "$BUNDLE_ID"
else
    echo "ERROR: Binary not found at $BIN"
    echo "For a full iOS app experience, open this package in Xcode:"
    echo "  open Package.swift"
    echo "Then select the MacRelayiOS scheme and an iOS simulator destination."
    exit 1
fi
