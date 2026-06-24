# MacRelay

Local-first macOS relay that bridges Codex CLI sessions to a companion iPhone app via HTTP + WebSocket.

## Current Capabilities

- **Mac relay server** — HTTP (pairing / snapshot / replay) + WebSocket (standard protocol, token or device-challenge auth)
- **iPhone pairing** — scan QR code / paste payload → one-time claim → WS connect → snapshot/replay/heartbeat
- **Device trust** — device registration with Keychain-persisted credentials, challenge-response auth (SHA256 / HMAC-SHA256)
- **Auto-reconnect** — heartbeat loop with exponential backoff, state-machine driven (unpaired → paired → connecting → connected → reconnecting → offline → authFailed)
- **Mac Inspector** — live relay status, pairing payload display with QR code, rotate/revoke pairing
- **iOS URL scheme** — `macrelay://pair?host=...&port=...&claim=...` launches the app and triggers pairing

## Architecture

```
AgentClientCore       — shared models, event store, relay protocol, auth, state machine
AgentClientIO         — iOS/Mac HTTP + WebSocket client library
AgentClientiOS        — SwiftUI views + view model for iPhone
AgentClientMacShell   — macOS SwiftUI app shell with Inspector
MacRelayiOS           — iOS @main app target (builds for simulator)
```

## Quick Start (macOS)

```bash
cd /private/tmp/MacRelay

# Full verification (no Codex quota consumed)
scripts/check.sh

# Start Mac shell
.build/debug/AgentClientMacShell

# Run a specific probe
.build/debug/MacRelayHTTPServerProbe
.build/debug/MacRelayWebSocketServerProbe
.build/debug/iPhoneSimClientProbe
```

## Quick Start (iOS Simulator)

```bash
# Requires Xcode with iOS 17+ simulator runtime
scripts/build-ios.sh

# Or the check script auto-detects simulator:
scripts/check.sh

## Quick Start (Real Device)

# Open Xcode App project (includes signing/provisioning)
open Apps/MacRelayiOSApp/MacRelayiOSApp.xcodeproj
scripts/build-ios-device.sh  # prints step-by-step guidance
```

## Pairing Flow

1. Start the Mac shell → Inspector → Pairing section shows QR code
2. Scan QR (or copy URI `macrelay://pair?...`) to iPhone simulator app
3. App completes claim → connects WebSocket → syncs snapshot + replay events
4. All subsequent auth uses device credential (Keychain-persisted)

See `docs/e2e-verification.md` for the full manual walkthrough.

## Protocol Docs

- `docs/MacRelay 协议文档.md` — HTTP/WS endpoints, auth flow, error codes, iPhone integration steps
- `docs/e2e-verification.md` — step-by-step manual verification

## Codex Quota ⚠️

**Live Codex probes are disabled by default.** They consume real model quota.

```bash
# These run real Codex sessions — use sparingly:
MACRELAY_RUN_LIVE_CODEX=1 .build/debug/RelayCommandLiveProbe
MACRELAY_RUN_LIVE_APPROVAL=1 .build/debug/RelayApprovalLiveProbe
```

All other probes (`check.sh`, `swift test`, `MacRelayHTTPServerProbe`, etc.) use local fixtures and do NOT consume quota.

## Not Yet Done

- App Store distribution pipeline
- Real approval.resolve live (probe is gated, draft exists)
- Production-level QR with encrypted payload
- iOS Keychain credential sharing between app extensions
