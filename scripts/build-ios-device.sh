#!/bin/bash
# Real device deployment — must use the Xcode App project.
# This script verifies the Xcode project and builds for iOS device
# (without signing, to prove the target compiles correctly).
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="Apps/MacRelayiOSApp/MacRelayiOSApp.xcodeproj"
SCHEME="MacRelayiOSApp"

echo "╔══════════════════════════════════════════════╗"
echo "║  MacRelay iOS — Real Device Verification    ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# Verify project structure
echo "==> Checking Xcode project"
if [ ! -d "$PROJECT" ]; then
    echo "ERROR: $PROJECT not found"
    exit 1
fi

xcodebuild -list -project "$PROJECT" 2>&1 | grep -q "$SCHEME" || {
    echo "ERROR: scheme '$SCHEME' not found in project"
    exit 1
}
echo "  ✅ Project valid, scheme '$SCHEME' found"

# Build for iOS device (no signing)
echo "==> Building for iOS device (CODE_SIGNING_ALLOWED=NO)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:" | head -5

if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "  ❌ Build failed — check errors above"
    exit 1
fi
echo ""

echo "╔══════════════════════════════════════════════╗"
echo "║  Real Device Deployment Steps               ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  1. Open the project:"
echo "     open $PROJECT"
echo ""
echo "  2. Select '$SCHEME' scheme (top-left)"
echo ""
echo "  3. Choose your connected iPhone as destination"
echo ""
echo "  4. Signing & Capabilities → Team: Personal Team"
echo ""
echo "  5. Press ⌘R to build, sign, and run on device"
echo ""
echo "Troubleshooting:"
echo "  - Device not listed: connect via USB, trust computer"
echo "  - Signing fails: verify Apple ID in Xcode → Accounts"
echo "  - Bundle ID conflict: change in target → General"
echo ""
echo "For simulator: ./scripts/build-ios.sh"
