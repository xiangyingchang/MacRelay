# Architecture, Security & Data Consistency Review

**Date**: 2026-07-12
**Reviewer**: Agent 8 (Architecture & Security Review)
**Scope**: Full Harness pipeline review after Agents 1-7
**Tests**: 446 passing, 0 failures

---

## Executive Summary

The MacRelay Harness pipeline is well-designed. The `Runtime -> RuntimeEvent -> Trace -> Reducer -> Snapshot -> Timeline -> Approval -> Replay` flow is clean, each component has a single responsibility, and the data layer uses proper abstractions (TraceStore, RunRepository, RunMetadataStore protocols with in-memory test doubles).

**Two P0 blockers** must be resolved before external-facing use:
1. API keys stored in plaintext UserDefaults instead of Keychain
2. No path traversal protection in tool executors

---

## Architecture Review

### 1. Runtime only connects via RuntimeEvent -- PASS

The runtime adapters (`CodexRuntimeAdapter`, `APIAgentRuntime`) produce `RuntimeEvent` objects. No code path allows the UI to mutate `SessionSnapshot` directly. The `MacRelayService` is the sole ingestion point, and it feeds events through the reducer.

One minor concern: `MacRelayService.updateSnapshotSettings()` allows the ViewModel to directly mutate `snapshot.settings` without going through an event. This is intentional (UI settings like planMode/permissionMode are not agent events) but creates a second mutation path. Acceptable for now.

### 2. Trace is the recovery fact source -- PASS

`RunRecoveryService.recover(runID:)` reads from `TraceReader`, replays through `SnapshotRebuilder.rebuild(from:)` and `TimelineBuilder().build(from:)`. Both snapshot and timeline are derived from the trace. `ReplayService` follows the same pattern. No component reads snapshot from disk independently.

### 3. Single Tool/Approval implementation -- PASS

- `ToolRegistry` is the only tool execution path
- `ApprovalPolicyEngine` is the only policy evaluation path
- `BuiltinTools` provides the 5 canonical tool definitions
- No duplicate implementations exist

### 4. UI doesn't bypass Query/Repository -- PASS

The `RunExplorerView` reads through `RunHistoryStore` (which composes `RunMetadataStore` + `ReplayService`). The timeline reads through `MacRelayService.timelineWithFallback()`. The ViewModel reads snapshot through `runtime.snapshot` (the reducer output). No direct array access from UI to internal state.

### 5. Seq is unique and monotonic -- PASS

`MacRelayService.runtimeEventSeq` is a `UInt64` incremented by 1 before each `withSeq()` call. `EventStore.append()` rejects events with `seq <= newestSeq`. `TraceReader` detects duplicate seqs (first occurrence wins) and reports gaps as warnings.

### 6. Trace, Snapshot, Timeline are consistent -- PASS

All three derive from the same `RuntimeEvent` stream:
- Trace: raw events written by `TraceWriter`
- Snapshot: events through `SessionStateReducer`
- Timeline: events through `TimelineBuilder`

`SnapshotRebuilder.rebuildWithTimeline()` processes the same event array once for both outputs, ensuring consistency.

---

## Data Consistency Review

### 1. Seq uniqueness and monotonicity -- PASS

`runtimeEventSeq` in `MacRelayService` is the single source. `EventStore` rejects duplicates. `TraceReader` detects and warns on duplicates/gaps.

### 2. Run lifecycle completeness -- PASS with note

All 7 states (`created`, `running`, `waitingApproval`, `completed`, `failed`, `cancelled`, `interrupted`) are reachable. State transitions are guarded by `AgentRun`'s mutating methods which return `Bool` for invalid transitions.

**Note**: The `interrupted` state is only set by `markInterrupted()` (called from `handleExited` in `RunLifecycleManager`). It requires the run to be non-terminal. This is correct -- a completed run followed by an app exit should not be re-labeled as interrupted.

### 3. Interrupted run detection -- PASS with P1 concern

`RunRecoveryService.recoverRun()` correctly:
- Detects `exited` events while run is non-terminal -> marks as `failed` with warning
- Detects traces ending in non-terminal state -> adds `incompleteRun` warning

**P1**: `RunLifecycleManager.handleExited()` does not clear `currentRun` when the run is already terminal. While this doesn't cause data corruption (the terminal run is already returned), it leaves a stale reference. If the same session starts a new run after an exit, `currentRun` still holds the old terminal run, and `handleRunStarted` will correctly replace it. Low risk but untidy.

### 4. Replay doesn't duplicate events -- PASS

`TraceReader.readAll()` deduplicates by seq (first occurrence wins). `SnapshotRebuilder` processes events in seq order. `EventStore` rejects events with `seq <= newestSeq`.

### 5. TraceReader handles corrupt lines -- PASS

`TraceReader.readAll()` catches decode errors per-line, appends a `.corruptLine` warning, and continues. `RunRecoveryService` converts these to `RecoveryWarning.corruptLine`. No crash path exists for corrupt trace files.

---

## Security Review

### 1. API keys only in Keychain -- FAIL (P0)

**File**: `Sources/AgentClientCore/APIProvider.swift:93-129`

`APIProviderStore` stores API keys in `UserDefaults` as plaintext JSON. `APIProvider.apiKey` is a plain `String` property that gets encoded to JSON and written to UserDefaults. Anyone with file access to `~/Library/Preferences/<bundle-id>.plist` can read all API keys.

In contrast, pairing credentials (`KeychainPairingCredentialStore`) and device trust (`KeychainDeviceTrustStore`) correctly use the Keychain.

**Fix**: `APIProviderStore` should use `kSecClassGenericPassword` in the Keychain, similar to `KeychainPairingCredentialStore`. The `apiKey` field should be excluded from UserDefaults serialization.

### 2. Shell and file operations can't bypass Approval -- FAIL (P0)

**File**: `Sources/AgentClientCore/APIAgentRuntime.swift:375-399, 466-482`

`APIAgentRuntime.executeToolCalls()` has its OWN approval logic (`checkApprovalNeeded()`) that completely bypasses the `ApprovalPolicyEngine`:

```swift
private func checkApprovalNeeded(...) -> Bool {
    let highRiskOperations = ["write_file", "run_shell_command", "delete_file"]
    if highRiskOperations.contains(function) {
        return approvalPolicy != "never"  // "never" = skip ALL approval
    }
    return false
}
```

When `approvalPolicy == "never"` (selected via "Full Access" permission mode), ALL tool calls execute without approval, including `run_shell_command` (which runs arbitrary shell commands via `/bin/zsh -c`). The `ApprovalPolicyEngine`'s critical-tool safety guard is never consulted.

The `ToolRegistry` has the correct guard (critical tools always require approval), but `APIAgentRuntime` doesn't use the registry for execution.

**Fix**: `APIAgentRuntime` should route tool execution through `ToolRegistry.executeWithApproval()`, which correctly consults the `ApprovalPolicyEngine`. The standalone `checkApprovalNeeded()` should be removed.

### 3. alwaysAllow has reasonable scope -- PASS with P1

`ApprovalPolicyEngine.effectivePolicyForOverride()` correctly downgrades `alwaysAllow` to `.ask` for critical-risk tools. Session overrides are scoped to the current session (not persisted across restarts).

**P1**: `alwaysAllow` without a workspace scope applies globally across all paths. The `setAlwaysAllow(tool:workspace:)` convenience method defaults to `workspace: nil`, which creates a global override. This is by design but the UI should warn users when setting a global always-allow.

### 4. Path operations are workspace-bounded -- FAIL (P0)

**File**: `Sources/AgentClientCore/BuiltinTools.swift:336-341`

```swift
private func resolvePath(_ path: String, relativeTo workspace: String) -> String {
    if path.hasPrefix("/") {
        return path  // Absolute paths are used as-is
    }
    return (workspace as NSString).appendingPathComponent(path)
}
```

No validation that the resolved path stays within the workspace. An attacker-controlled tool call with `path: "../../../etc/passwd"` would read arbitrary files. With `path: "/etc/passwd"` (absolute), it bypasses the workspace entirely.

The `read_file`, `list_files`, `write_file`, and `search_text` executors all use this function without additional validation.

**Fix**: After resolving, normalize the path and verify it starts with the workspace path:
```swift
let resolved = URL(fileURLWithPath: resolvedPath).standardized.path
guard resolved.hasPrefix(workspace) else {
    return ToolResult(callID: call.id, success: false, error: "Path outside workspace")
}
```

### 5. Tool parameters are validated before execution -- PARTIAL (P1)

`ToolRegistry.validateParameters()` checks that required parameters exist in the call. However:
- No type validation (a string param could receive garbage)
- No value validation (paths not checked for traversal, commands not checked for injection)
- The `inputSchema` JSON Schema is not used for actual validation, only for `required` field presence

### 6. Critical tools always require approval -- PASS (in PolicyEngine)

`ApprovalPolicyEngine.effectivePolicyForOverride()` and `effectivePolicyForRule()` both downgrade `.allow` to `.ask` for critical-risk tools. This is the correct safety guard.

**However**: This guard is only effective when tools go through the `ApprovalPolicyEngine`. The `APIAgentRuntime` bypass (P0 #2 above) means this guard is not enforced for API-mode tool execution.

---

## Findings Summary

### P0 -- Must fix before Tailscale/MCP/Evaluation phase

| # | Category | Issue | File |
|---|----------|-------|------|
| P0-1 | Security | API keys stored in plaintext UserDefaults, not Keychain | `APIProvider.swift:93-129` |
| P0-2 | Security | APIAgentRuntime bypasses ApprovalPolicyEngine for tool execution | `APIAgentRuntime.swift:375-399, 466-482` |
| P0-3 | Security | No path traversal protection in tool executors (read/write/list/search) | `BuiltinTools.swift:336-341` |

### P1 -- Should fix soon

| # | Category | Issue | File |
|---|----------|-------|------|
| P1-1 | Security | `alwaysAllow` without workspace scope is global by default | `ApprovalPolicyEngine.swift:159-173` |
| P1-2 | Security | Tool parameter validation only checks presence, not type/value | `ToolRegistry.swift:316-343` |
| P1-3 | Data | RunLifecycleManager.handleExited does not clear currentRun when run is terminal | `RunLifecycleManager.swift:174-183` |
| P1-4 | Security | `run_shell_command` has no sandboxing (runs arbitrary commands via `/bin/zsh -c`) | `BuiltinTools.swift:296-329` |
| P1-5 | Security | `APIAgentRuntime.checkApprovalNeeded()` uses hardcoded risk list, not ToolDefinition.riskLevel | `APIAgentRuntime.swift:466-482` |

### P2 -- Technical debt

| # | Category | Issue | File |
|---|----------|-------|------|
| P2-1 | Debt | Deprecated `runtimeEvent(from:)` maps unknown events to `.settingsUpdated` instead of `.unknown` | `SessionStateReducer.swift:531-677` |
| P2-2 | Debt | Deprecated `actions(from: CodexAppServerEvent)` still exists alongside `actions(from: RuntimeEvent)` | `SessionStateReducer.swift:478-527` |
| P2-3 | Debt | `APIAgentRuntime.executeTool()` uses hardcoded "Tool {function} executed" instead of real execution | `APIAgentRuntime.swift:428-464` |
| P2-4 | Debt | `TraceWriter.readAll()` throws on corrupt lines while `TraceReader.readAll()` skips them gracefully | `TraceWriter.swift:97-127` vs `TraceReader.swift:68-124` |
| P2-5 | Debt | `MacRelayService` has two separate seq counters (EventStore seq vs runtimeEventSeq) | `MacRelayService.swift:65` |

### NOT to do now

1. **MCP protocol support** -- Requires architectural decisions about tool routing that depend on Tailscale networking.
2. **Multi-tenant isolation** -- Current single-user design is appropriate for the evaluation phase.
3. **Trace file encryption** -- Traces don't contain API keys (the runtime adapters strip them). File-level encryption is a future concern.
4. **Distributed tracing** -- The current local-first design is correct for the current scope.
5. **Removing deprecated code** -- The deprecated `CodexAppServerEvent` codepath is still needed for backward compatibility with the Codex CLI runtime. Remove only after Codex is fully migrated to RuntimeEvent.

---

## Recommendation

**Ready for Tailscale / MCP / Evaluation phase?**

**Conditionally YES**, after fixing P0-1 (API keys in Keychain) and P0-3 (path traversal). These are straightforward fixes (~1-2 hours each).

P0-2 (APIAgentRuntime approval bypass) should also be fixed but is lower risk in practice because the "Full Access" mode is user-initiated and explicitly documented as dangerous. It should be fixed before any external distribution.

The architecture is solid. The pipeline is clean. The test coverage (446 tests) is good for the core components. The data layer abstractions (protocol + in-memory doubles) make the codebase testable and extensible.

**Key strengths:**
- Clean separation: RuntimeEvent is the single interface between transport and domain
- Forward compatibility: unknown event types/payloads are preserved, never crash
- Crash recovery: Trace is the fact source, snapshot/timeline are derived
- Thread safety: NSLock on all mutable stores

**Key risks for next phase:**
- Tailscale networking will expose the approval bypass to remote attackers (P0-2 becomes higher priority)
- MCP tool integration must go through the ToolRegistry path, not a parallel path
- The hardcoded risk list in APIAgentRuntime must be replaced by ToolDefinition.riskLevel before adding more tools
