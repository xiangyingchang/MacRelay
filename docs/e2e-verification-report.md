# E2E Pipeline Verification Report

**Date**: 2026-07-11
**Branch**: main (worktree agent-a7727c626c97e895a)
**Test suite**: 276 tests, 0 failures

## Test Environment

- Platform: macOS (Darwin 25.5.0, x86_64)
- Swift toolchain: Xcode default
- Test framework: XCTest + Testing Library 1902
- All 276 tests pass before and after fixes

## Pipeline Verification: Stage by Stage

### Stage 1: Runtime -> RuntimeEvent

**CodexRuntimeAdapter** (`Sources/AgentClientCore/CodexRuntimeAdapter.swift`):
- Maps all Codex JSON-RPC notifications to correct RuntimeEvent types
- `thread/started` -> `.sessionStarted` (with sessionID from thread ID)
- `turn/started` -> `.turnStarted` (with turnID and input)
- `item/agentMessage/delta` -> `.assistantDelta`
- `turn/completed` -> `.turnCompleted`
- `turn/error` -> `.turnError`
- `error` -> `.error`
- `thread/settings/updated` -> `.settingsUpdated`
- `item/completed` (fileChange) -> `.fileChangeDetected`
- `turn/diff/updated` -> `.diffUpdated`
- Server requests (approvals) -> `.approvalRequested`
- Unknown notifications -> `.unknown` with `.generic` payload (preserved)
- `.exit` -> `.exited`
- `.response`, `.stderr`, `.raw` -> filtered (correct)

**ClaudeCodeRuntime** (`Sources/AgentClientMacShell/ClaudeCodeRuntime.swift`):
- Normalizes events before forwarding: `item/progress` -> `item/agentMessage/delta`, `turn/error` -> `error`
- Injects user input from `pendingDraft` into `turn/started` via `normalizedEvent()`
- Uses augmented event for BOTH `onEventReceived` AND `apply()` (correct)

**APIAgentRuntime** (`Sources/AgentClientCore/APIAgentRuntime.swift`):
- Emits standard Codex-compatible notifications for most events
- Tool call events use non-standard method names (`tool/call/requested`, `tool/call/completed`) that map to `.unknown` in CodexRuntimeAdapter -- these are invisible in timeline and trace (known limitation, not a production bug since API runtime is secondary)

### Stage 2: RuntimeEvent -> Trace (TraceWriter)

**TraceWriter** (`Sources/AgentClientCore/TraceWriter.swift`):
- JSONL format with ISO8601 dates, sorted keys
- `synchronizeFile()` after every write (crash-safe)
- Thread-safe via NSLock
- Correct seq tracking via `lastSeq = event.seq ?? lastSeq`
- `readAll()` correctly reconstructs events from disk
- `read(afterSeq:)` correctly filters by seq

**TraceReader** (`Sources/AgentClientCore/TraceReader.swift`):
- Version-aware: skips events with version > `currentVersion`
- Sorts by seq after reading (handles out-of-order appends)
- Round-trip verified in `HarnessPipelineTests.testTraceReplay_normalCodingRun`

### Stage 3: RuntimeEvent -> Reducer -> Snapshot

**SessionStateReducer** (`Sources/AgentClientCore/SessionStateReducer.swift`):
- `actions(from: RuntimeEvent)` handles all RuntimeEventType cases
- `.sessionStarted` -> `.threadStarted` (clears previous state)
- `.turnStarted` -> `.turnStarted` (archives previous turn if different ID)
- `.assistantDelta` -> `.assistantDelta` (appends to activeTurn.assistantText)
- `.turnCompleted` -> `.turnCompleted` (archives turn, sets status)
- `.turnError` -> `.error` (sets lastError, status=systemError)
- `.approvalRequested` -> `.approvalRequested` (creates CodexApprovalRequest)
- `.approvalResolved` -> `.approvalResolved` (clears pending, restores status)
- `.fileChangeDetected` -> `.fileChangeUpdated`
- `.diffUpdated` -> `.diffUpdated`
- `.error` -> `.error`
- `.exited` -> `.exited`
- `.settingsUpdated` -> `.settingsUpdated`
- `.runStarted/Completed/Failed/Cancelled/WaitingApproval/Resumed` -> corresponding actions
- `.unknown` -> no actions (correct)

**SnapshotRebuilder** (`Sources/AgentClientCore/SnapshotRebuilder.swift`):
- Correctly replays events through reducer to rebuild snapshot
- `rebuildWithTimeline` returns both snapshot and timeline in single pass

### Stage 4: Snapshot -> WebSocket -> iOS

**MacRelayService** (`Sources/AgentClientCore/MacRelayService.swift`):
- `snapshotEnvelope()` includes all required fields
- `RelaySessionSnapshotPayload` carries: threadID, cwd, status, model, effort, planMode, permissionMode, provider, assistantText, userMessage, turns, availableModels, changedFiles, rateLimitPlanType, errorMessage, messages
- UI settings (planMode, permissionMode, provider) injected separately from runtime snapshot

**MacRelayWebSocketServer** (`Sources/AgentClientCore/MacRelayWebSocketServer.swift`):
- Pairing token and device-trust auth supported
- `handleRelayCommand` dispatches snapshot.get, replay.from, heartbeat, session commands
- `snapshot.get` injects grouped sessions, messages, and activeSessionID from dispatcher
- Broadcast pushes snapshots to all authenticated connections

### Stage 5: RuntimeEvent -> Timeline

**TimelineBuilder** (`Sources/AgentClientCore/TimelineBuilder.swift`):
- Stateless: `build(from:)` processes full event list
- Handles: turnStarted (user message), assistantDelta (accumulate), assistantMessageCompleted (flush), turnCompleted (flush + finalResult), turnError (flush + error), toolCallRequested/Completed/Failed, approvalRequested/Resolved, fileChangeDetected, error
- Ignores: sessionStarted/Stopped/Selected, diffUpdated, exited, settingsUpdated, all run lifecycle events, unknown

### Stage 6: Approval Flow

- Approval request: runtime emits `serverRequest` -> CodexRuntimeAdapter -> `.approvalRequested` -> reducer sets `waitingOnApproval` status
- Approval resolution: runtime calls `resolveApproval()` -> sends JSON-RPC response to app-server -> app-server continues turn
- **Bug found and fixed**: CodexRuntimeBridge used original event for local reducer, missing user message in turn/started

## Bugs Found and Fixed

### Bug 1: CodexRuntimeBridge local snapshot missing user message (FIXED)

**File**: `Sources/AgentClientMacShell/CodexRuntimeBridge.swift`
**Root cause**: In `handle()`, `apply(reducer.actions(from: event))` used the original CodexAppServerEvent instead of the augmented event. The augmented event (which includes the user's input from `pendingDraft` in `turn/started`) was correctly sent to the relay service via `onEventReceived`, but the local reducer received the original event without the input.
**Impact**: The CodexRuntime's local `snapshot.activeTurn.userMessage` was nil for turn/started events. The relay service (and iOS) received the correct data, but the Mac UI's local snapshot was incomplete.
**Fix**: Changed `apply(reducer.actions(from: event))` to `apply(reducer.actions(from: augmentedEvent))`.
**Note**: ClaudeCodeRuntime already handled this correctly -- its `normalizedEvent()` produces the augmented event and uses it for both `onEventReceived` and `apply()`.

### Bug 2: RuntimeEvent seq duplication in trace (FIXED)

**File**: `Sources/AgentClientCore/MacRelayService.swift`
**Root cause**: RuntimeEvent seq was assigned from `newestSeq` (the EventStore's last StoredRelayEvent seq). When `ingest()` produced no StoredRelayEvent (e.g., for unknown notifications), `newestSeq` didn't advance, causing consecutive RuntimeEvents to receive the same seq value.
**Impact**: `TraceWriter.read(afterSeq:)` could miss events with duplicate seqs. For example, if two consecutive events both have seq=5, reading after seq=4 returns both, but reading after seq=5 returns neither -- the second event is lost.
**Fix**: Added a dedicated `runtimeEventSeq` counter (starting at 0, incrementing by 1) for RuntimeEvent seq assignment, independent of the EventStore's seq. Both `ingestWithRuntimeEvent` and `ingestRuntimeEvent` now use this counter.

## Test Coverage Gaps

1. **CodexRuntimeBridge augmented event path**: No test verifies that the local snapshot's `activeTurn.userMessage` is populated from `pendingDraft` during `turn/started`. Existing tests go through `MacRelayService.ingestWithRuntimeEvent()` which bypasses the CodexRuntimeBridge.

2. **RuntimeEvent seq monotonicity**: No test verifies that RuntimeEvents in the trace have strictly increasing seqs, especially when the deprecated ingest path produces no StoredRelayEvent.

3. **APIAgentRuntime tool calls**: No test verifies that tool call events from APIAgentRuntime appear in the timeline or trace. Currently they're silently dropped as `.unknown` events.

4. **Approval resolution in trace**: No test verifies that approval resolution events appear in the trace when a user approves/rejects through the runtime.

## Recommendations

1. **Add integration test for CodexRuntimeBridge local snapshot**: Test that `handle()` correctly populates `activeTurn.userMessage` from `pendingDraft`.

2. **Add seq monotonicity test**: Verify that `runtimeEvents` always have strictly increasing seqs after multiple `ingestWithRuntimeEvent` calls.

3. **Consider APIAgentRuntime tool call mapping**: The API runtime emits `tool/call/requested` and `tool/call/completed` which become `.unknown` events. If API runtime becomes primary, these should be mapped to proper RuntimeEvent types.

4. **Consider emitting approvalResolved events**: Currently, approval resolutions are sent as JSON-RPC responses to the app-server but not recorded as RuntimeEvents in the trace. This means the trace and timeline don't show when an approval was resolved.
