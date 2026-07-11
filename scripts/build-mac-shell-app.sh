#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/.build/AgentClientMacShell.app"
MACOS="$APP/Contents/MacOS"
LAUNCH_AFTER_BUILD=false

if [[ "${1:-}" == "--launch" ]]; then
    LAUNCH_AFTER_BUILD=true
elif [[ $# -gt 0 ]]; then
    echo "usage: $0 [--launch]" >&2
    exit 2
fi

cd "$ROOT_DIR"
swift build --product AgentClientMacShell
PRODUCT="$(swift build --show-bin-path)/AgentClientMacShell"

rm -rf "$APP"
mkdir -p "$MACOS" "$APP/Contents/Resources"
cp "$PRODUCT" "$MACOS/AgentClientMacShell"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>AgentClientMacShell</string>
    <key>CFBundleIdentifier</key>
    <string>com.xiangyingchang.macrelay.macshell</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AgentClientMacShell</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "$APP"

if [[ "$LAUNCH_AFTER_BUILD" == true ]]; then
    # A bare SwiftPM executable does not provide a reliable macOS Text Services
    # context. Kill every stale copy, then launch the signed app bundle so IME
    # candidate-window coordinates and marked-text commits use AppKit correctly.
    pkill -x AgentClientMacShell 2>/dev/null || true
    open "$APP"
fi
