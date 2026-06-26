#!/bin/bash
# Ad-hoc verification: wsPort chain (4 files changed)
# Cleanup: removed after execution
set -euo pipefail
cd /private/tmp/MacRelay

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  ✅ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ❌ $1"; }

echo "╔════════════════════════════════════╗"
echo "║ ad-hoc: wsPort fix                ║"
echo "╚════════════════════════════════════╝"

# 1. swift build
swift build 2>&1 | tail -1 && pass "swift build" || fail "swift build"

# 2. swift test
swift test 2>&1 | tail -1 | grep -q passed && pass "swift test" || fail "swift test"

# 3. MacRelayHTTPServerProbe (validates wsPort in payload)
.build/debug/MacRelayHTTPServerProbe 2>&1 | tail -1 | grep -q passed && pass "HTTPServerProbe" || fail "HTTPServerProbe"

# 4. Start ManualVerificationServer, check wsPort in /pairing
.build/debug/ManualVerificationServer &
PID=$!
sleep 2
WS=$(curl -s http://127.0.0.1:48731/pairing | python3 -c "import json,sys; print(json.load(sys.stdin).get('wsPort',0))")
[ "$WS" = "48732" ] && pass "wsPort in /pairing = $WS" || fail "wsPort in /pairing = $WS"

# 5. Check wsPort in /pairing/claim response
CLAIM=$(curl -s http://127.0.0.1:48731/pairing | python3 -c "import json,sys; print(json.load(sys.stdin)['claim'])")
CWS=$(curl -s "http://127.0.0.1:48731/pairing/claim?claim=$CLAIM" | python3 -c "import json,sys; print(json.load(sys.stdin).get('wsPort',0))")
[ "$CWS" = "48732" ] && pass "wsPort in claim = $CWS" || fail "wsPort in claim = $CWS"

kill $PID 2>/dev/null; wait $PID 2>/dev/null || true

# Summary
echo ""
echo "pass=$PASS fail=$FAIL"
[ $FAIL -eq 0 ] && echo "✅ wsPort chain verified" || echo "❌ $FAIL failure(s)"
