#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

LIVE_CODEX="${MACRELAY_RUN_LIVE_CODEX:-0}"
LIVE_APPROVAL="${MACRELAY_RUN_LIVE_APPROVAL:-0}"

echo "==> MacRelay Check"
echo "    Live Codex:   ${LIVE_CODEX}"
echo "    Live Approval: ${LIVE_APPROVAL}"
echo ""

FAIL=0

run() {
    local label="$1"; shift
    if "$@" &>/dev/null; then
        echo "  ✅ $label"
    else
        echo "  ❌ $label FAILED"
        ((FAIL++)) || true
    fi
}

echo "── Build ──"
swift build || { echo "BUILD FAILED"; exit 1; }
echo ""

echo "── Tests ──"
swift test || ((FAIL++))
echo ""

echo "── Probes ──"
run "MacRelayHTTPServerProbe"              .build/debug/MacRelayHTTPServerProbe
run "MacRelayWebSocketServerProbe"         .build/debug/MacRelayWebSocketServerProbe
run "RelayRuntimeCommandDispatcherProbe"   .build/debug/RelayRuntimeCommandDispatcherProbe
run "AgentClientIOProbe"                   .build/debug/AgentClientIOProbe
run "ChallengeSignerProbe"                 .build/debug/ChallengeSignerProbe
run "PairingURIProbe"                      .build/debug/PairingURIProbe
echo ""

echo "── Live Probes ──"
if [ "$LIVE_CODEX" = "1" ]; then
    run "RelayCommandLiveProbe (LIVE)"     .build/debug/RelayCommandLiveProbe
else
    echo "  ⏭  RelayCommandLiveProbe (set MACRELAY_RUN_LIVE_CODEX=1)"
fi
if [ "$LIVE_APPROVAL" = "1" ]; then
    run "RelayApprovalLiveProbe (LIVE)"    .build/debug/RelayApprovalLiveProbe
else
    echo "  ⏭  RelayApprovalLiveProbe (set MACRELAY_RUN_LIVE_APPROVAL=1)"
fi
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo "All checks passed ✅"
else
    echo "$FAIL check(s) failed ❌"
    exit 1
fi
