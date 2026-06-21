# MacRelay

Local-first macOS relay prototype for controlling Codex CLI / `codex app-server` sessions and preparing iPhone handoff.

> Previous working name: `AgentClientM1Prototype`.

M1 engineering skeleton for the local-first Codex CLI client.

Current scope:

- `AgentClientCore`: shared Swift core for macOS and iPhone.
- `AgentClientMacMock`: command-line mock of the future Mac relay shell.
- `RelayCoreFixtureProbe`: local fixture that validates reducer -> relay protocol -> event store flow.

This prototype intentionally avoids UI decisions. UI and interaction quality will be designed separately against the Hermes Desktop / Lody references.

Verified core copied from `/private/tmp/AgentClientCorePrototype`:

- `CodexAppServerClient`
- `JSONRPCWriter`
- `LineDelimitedJSONBuffer`
- `CodexApprovalRequest`
- `CodexTurnDiffUpdated`
- `CodexFileChangeUpdated`
- `SessionStateReducer`
- `RelayProtocol`
- `EventStore`

Next engineering steps:

- Replace `AgentClientMacMock` with a SwiftUI/AppKit Mac app target.
- Wire `CodexAppServerClient` to `SessionStateReducer`.
- Add a real WebSocket relay server.
- Add QR pairing and device trust.
- Add iPhone client after Mac relay shell is stable.

## Repository layout

- `Sources/AgentClientCore`: shared relay protocol, event reducer, Codex app-server client, replay store, relay service skeleton, and local HTTP relay probe server.
- `Sources/AgentClientMacShell`: SwiftUI macOS shell prototype.
- `Sources/*Probe`: executable probes for schema, relay, HTTP, and fixture validation.
- `Tests/AgentClientCoreTests`: reducer and formatting tests.
- `docs/`: product requirements, UI baseline, Mac Relay design, iPhone IA, and execution plan.

## Validation

```bash
swift build
.build/debug/MacRelayServiceFixtureProbe
.build/debug/MacRelayHTTPServerProbe
.build/debug/RelayCommandFixtureProbe
.build/debug/SandboxPayloadProbe
.build/debug/SettingsUpdateSchemaProbe
swift test
```
