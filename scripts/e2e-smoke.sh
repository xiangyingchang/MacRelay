#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "╔══════════════════════════════════════════════╗"
echo "║   MacRelay End-to-End Smoke Test            ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Step 1: Build ──────────────────────────────────
echo "── Step 1: Build ──"
swift build
echo ""

# ── Step 2: Non-live probes ────────────────────────
echo "── Step 2: Probes ──"
PROBES=(
    .build/debug/MacRelayHTTPServerProbe
    .build/debug/MacRelayWebSocketServerProbe
    .build/debug/RelayRuntimeCommandDispatcherProbe
    .build/debug/AgentClientIOProbe
    .build/debug/RealStateMachineLoopProbe
    .build/debug/ChallengeSignerProbe
    .build/debug/iPhoneSimClientProbe
)

PASS=0; FAIL=0
for probe in "${PROBES[@]}"; do
    if "$probe" &>/dev/null; then
        echo "  ✅ $(basename "$probe")"
        ((PASS++)) || true
    else
        echo "  ❌ $(basename "$probe") FAILED"
        ((FAIL++)) || true
    fi
done
echo "  Passed: $PASS  Failed: $FAIL"
echo ""

# ── Step 3: Live probes (skipped by default) ──────
echo "── Step 3: Live probes ──"
echo "  RelayCommandLiveProbe: skipped (requires MACRELAY_RUN_LIVE_CODEX=1)"
echo "  RelayApprovalLiveProbe: skipped (requires MACRELAY_RUN_LIVE_APPROVAL=1)"
echo ""

# ── Step 4: Swift test ─────────────────────────────
echo "── Step 4: Unit tests ──"
swift test
echo ""

# ── Step 5: iOS App (if simulator available) ──────
echo "── Step 5: iOS App ──"
if xcrun --sdk iphonesimulator --show-sdk-path &>/dev/null 2>&1; then
    echo "  Running build-ios.sh ..."
    if ./scripts/build-ios.sh 2>&1 | head -5; then
        echo "  ✅ iOS App installed in simulator"
    else
        echo "  ⚠️  iOS App build failed (may need Xcode 26+ / iOS 17 runtime)"
    fi
else
    echo "  ⚠️  iOS simulator SDK not available — skipping"
fi
echo ""

# ── Step 6: Manual pairing instructions ───────────
echo "── Step 6: Manual Pairing ──"
echo "  To complete the E2E flow manually:"
echo "  1. Start Mac shell:  .build/debug/AgentClientMacShell"
echo "  2. Check Mac Inspector → Pairing for QR code + payload"
echo "  3. iOS Simulator App → Pairing tab → paste payload → click Claim"
echo "  4. Switch to Session tab → verify connection + snapshot"
echo "  See docs/e2e-verification.md for full instructions."
echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   Smoke test complete.                      ║"
echo "╚══════════════════════════════════════════════╝"
