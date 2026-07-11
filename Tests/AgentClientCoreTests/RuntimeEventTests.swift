import XCTest
@testable import AgentClientCore

// MARK: - RuntimeEvent v1 Tests

@MainActor
final class RuntimeEventTests: XCTestCase {

    // MARK: - Schema Tests

    func test_runtimeEventIsImmutable() {
        let event = RuntimeEvent(
            runtime: .claudeCode,
            type: .turnStarted,
            payload: .turnStarted(turnID: "turn-1", input: "fix the bug")
        )
        XCTAssertNil(event.seq)
        XCTAssertEqual(event.version, 1)
    }

    func test_withSeqCreatesNewEventWithSeqAssigned() {
        let original = RuntimeEvent(
            runtime: .codex,
            type: .turnStarted,
            payload: .turnStarted(turnID: nil, input: nil)
        )
        XCTAssertNil(original.seq)

        let withSeq = original.withSeq(42)
        XCTAssertEqual(withSeq.seq, 42)
        XCTAssertEqual(withSeq.id, original.id)
        XCTAssertNil(original.seq) // immutable
    }

    func test_runtimeEventHasAllRequiredFields() {
        let event = RuntimeEvent(
            sessionID: "s1", runID: "r1",
            runtime: .claudeCode, type: .turnStarted,
            payload: .turnStarted(turnID: "turn-1", input: "fix the bug")
        )
        XCTAssertFalse(event.id.isEmpty)
        XCTAssertEqual(event.sessionID, "s1")
        XCTAssertEqual(event.runID, "r1")
        XCTAssertEqual(event.runtime, .claudeCode)
        XCTAssertEqual(event.type, .turnStarted)
    }

    // MARK: - RuntimeIdentifier

    func test_runtimeIdentifierCoversKnownProviders() {
        XCTAssertEqual(RuntimeIdentifier.codex.rawValue, "codex")
        XCTAssertEqual(RuntimeIdentifier.claudeCode.rawValue, "claude-code")
        XCTAssertEqual(RuntimeIdentifier.openAI.rawValue, "openai")
        XCTAssertEqual(RuntimeIdentifier.deepSeek.rawValue, "deepseek")
        XCTAssertEqual(RuntimeIdentifier.mimo.rawValue, "mimo")
        XCTAssertEqual(RuntimeIdentifier.anthropic.rawValue, "anthropic")
        XCTAssertEqual(RuntimeIdentifier.gemini.rawValue, "gemini")
        XCTAssertEqual(RuntimeIdentifier.local.rawValue, "local")
    }

    func test_runtimeIdentifier_fromMapsKnownStrings() {
        XCTAssertEqual(RuntimeIdentifier.from("codex"), .codex)
        XCTAssertEqual(RuntimeIdentifier.from("openai"), .openAI)
        XCTAssertEqual(RuntimeIdentifier.from("mimo"), .mimo)
    }

    func test_runtimeIdentifier_fromMapsUnknownToCustom() {
        XCTAssertEqual(RuntimeIdentifier.from("future-quantum"), .custom)
    }

    func test_runtimeIdentifierCodable_decodesUnknownAsCustom() throws {
        let json = "\"quantum-ai-v2\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RuntimeIdentifier.self, from: data)
        XCTAssertEqual(decoded, .custom)
    }

    // MARK: - RuntimeEventType Forward Compatibility

    func test_runtimeEventTypeCodable_decodesUnknownAsUnknown() throws {
        let json = "\"agent.reflection.completed\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RuntimeEventType.self, from: data)
        if case .unknown = decoded {} else { XCTFail("Expected .unknown, got \(decoded)") }
    }

    // MARK: - RuntimeEventPayload Forward Compatibility

    func test_encodeDecodeRoundTrip_allKnownPayloads() throws {
        let payloads: [(RuntimeEventPayload, String)] = [
            (.sessionStarted(sessionID: "s1", cwd: "/tmp"), "sessionStarted"),
            (.turnStarted(turnID: "t1", input: "fix"), "turnStarted"),
            (.turnCompleted(turnID: "t1"), "turnCompleted"),
            (.assistantDelta(text: "hello"), "assistantDelta"),
            (.toolCall(name: "read_file", params: nil), "toolCall"),
            (.approvalRequested(requestID: 1, tool: "run", command: nil, riskLevel: nil), "approvalRequested"),
            (.approvalResolved(requestID: 1, decision: "accept"), "approvalResolved"),
            (.fileChange(path: "/f", changeKind: "modified"), "fileChange"),
            (.error(message: "err", code: nil), "error"),
            (.exited(code: 0), "exited"),
            (.settingsUpdated(model: "m", effort: "e"), "settingsUpdated"),
            (.generic(method: "x", params: nil), "generic"),
        ]

        for (original, name) in payloads {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(RuntimeEventPayload.self, from: data)
            XCTAssertEqual(decoded, original, "Round-trip failed for \(name)")
        }
    }

    func test_unknownPayload_decodesFromFutureEvent() throws {
        let json = """
        {"case":"agent.multiStepReflection","steps":5,"result":"improved"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RuntimeEventPayload.self, from: data)

        if case let .unknown(discriminator, _) = decoded {
            XCTAssertEqual(discriminator, "agent.multiStepReflection")
        } else {
            XCTFail("Expected unknown for future payload type")
        }
    }

    // MARK: - Full Event Round-Trip

    func test_fullEvent_encodeDecodeRoundTrip() throws {
        let event = RuntimeEvent(
            id: "test-id", seq: 99, version: 1,
            timestamp: Date(timeIntervalSince1970: 1000000),
            sessionID: "s1", runID: "r1",
            runtime: .claudeCode, type: .turnStarted,
            payload: .turnStarted(turnID: "t1", input: "fix")
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(RuntimeEvent.self, from: data)

        XCTAssertEqual(decoded.id, "test-id")
        XCTAssertEqual(decoded.seq, 99)
        XCTAssertEqual(decoded.sessionID, "s1")
        XCTAssertEqual(decoded.runID, "r1")
        XCTAssertEqual(decoded.runtime, .claudeCode)
        XCTAssertEqual(decoded.type, .turnStarted)
    }

    func test_fullEvent_withUnknownTypeAndPayload() throws {
        let json = """
        {
            "id": "f1", "seq": null, "version": 1, "timestamp": 1000000,
            "sessionID": "s1", "runID": null, "runtime": "quantum-ai",
            "type": "agent.reflection.completed",
            "payload": {"case":"agent.multiStepReflection","steps":5}
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RuntimeEvent.self, from: data)

        XCTAssertEqual(decoded.runtime, .custom)
        if case .unknown = decoded.type {} else { XCTFail("Expected .unknown type") }
        if case let .unknown(d, _) = decoded.payload {
            XCTAssertEqual(d, "agent.multiStepReflection")
        } else { XCTFail("Expected .unknown payload") }
    }

    // MARK: - CodexRuntimeAdapter Tests

    func test_adapterConverts_threadStarted() {
        let adapter = CodexRuntimeAdapter()
        let events = adapter.adapt(
            .notification(method: "thread/started", params: ["id": "t1", "cwd": "/tmp"]),
            sessionID: "old"
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .sessionStarted)
        XCTAssertEqual(events[0].runtime, .codex)
        XCTAssertEqual(events[0].sessionID, "t1") // updated to new thread ID
    }

    func test_adapterConverts_turnStarted() {
        let adapter = CodexRuntimeAdapter()
        let events = adapter.adapt(
            .notification(method: "turn/started", params: ["turn_id": "t1", "input": "fix"]),
            sessionID: "s1"
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .turnStarted)
        if case let .turnStarted(tid, input) = events[0].payload {
            XCTAssertEqual(tid, "t1")
            XCTAssertEqual(input, "fix")
        } else { XCTFail("Expected turnStarted") }
    }

    func test_adapterConverts_assistantDelta() {
        let adapter = CodexRuntimeAdapter()
        let events = adapter.adapt(
            .notification(method: "item/agentMessage/delta", params: ["delta": "Hello"]),
            sessionID: "s1"
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .assistantDelta)
        if case let .assistantDelta(text) = events[0].payload {
            XCTAssertEqual(text, "Hello")
        } else { XCTFail("Expected assistantDelta") }
    }

    func test_adapterConverts_error() {
        let adapter = CodexRuntimeAdapter()
        let events = adapter.adapt(
            .notification(method: "error", params: ["error": ["message": "timeout", "code": "ETIMEDOUT"]]),
            sessionID: "s1"
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .error)
        if case let .error(msg, code) = events[0].payload {
            XCTAssertEqual(msg, "timeout")
            XCTAssertEqual(code, "ETIMEDOUT")
        } else { XCTFail("Expected error") }
    }

    func test_adapterConverts_exit() {
        let adapter = CodexRuntimeAdapter()
        #if os(macOS)
        let events = adapter.adapt(.exit(code: 137, reason: .uncaughtSignal), sessionID: "s1")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .exited)
        if case let .exited(code) = events[0].payload {
            XCTAssertEqual(code, 137)
        } else { XCTFail("Expected exited") }
        #endif
    }

    func test_adapterIgnores_responseAndStderr() {
        let adapter = CodexRuntimeAdapter()
        XCTAssertTrue(adapter.adapt(.response(id: 1, result: [:], error: nil)).isEmpty)
        XCTAssertTrue(adapter.adapt(.stderr("debug")).isEmpty)
        XCTAssertTrue(adapter.adapt(.raw("unparseable")).isEmpty)
    }

    func test_adapterPreservesUnknownNotifications() {
        let adapter = CodexRuntimeAdapter()
        let events = adapter.adapt(
            .notification(method: "custom/future/event", params: ["key": "value"]),
            sessionID: "s1"
        )
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .unknown)
        if case let .generic(method, params) = events[0].payload {
            XCTAssertEqual(method, "custom/future/event")
            XCTAssertEqual(params?["key"], "value")
        } else { XCTFail("Expected generic payload") }
    }

    // MARK: - Reducer: RuntimeEvent → Actions → Snapshot

    func test_reducer_sessionStartedFromRuntimeEvent() {
        let reducer = SessionStateReducer()
        var snapshot = SessionSnapshot()

        let event = RuntimeEvent(
            runtime: .codex, type: .sessionStarted,
            payload: .sessionStarted(sessionID: "new-thread", cwd: "/tmp")
        )
        let actions = reducer.actions(from: event)
        for action in actions { reducer.reduce(&snapshot, action: action) }

        XCTAssertEqual(snapshot.threadID, "new-thread")
        XCTAssertEqual(snapshot.cwd, "/tmp")
        XCTAssertTrue(snapshot.completedTurns.isEmpty)
        XCTAssertNil(snapshot.lastError)
    }

    func test_reducer_turnStartedFromRuntimeEvent() {
        let reducer = SessionStateReducer()
        var snapshot = SessionSnapshot()
        snapshot.threadID = "t1"

        let event = RuntimeEvent(
            runtime: .claudeCode, type: .turnStarted,
            payload: .turnStarted(turnID: "turn-1", input: "fix login")
        )
        let actions = reducer.actions(from: event)
        for action in actions { reducer.reduce(&snapshot, action: action) }

        XCTAssertEqual(snapshot.activeTurn?.id, "turn-1")
        XCTAssertEqual(snapshot.activeTurn?.userMessage, "fix login")
        XCTAssertEqual(snapshot.status, .active)
    }

    func test_reducer_assistantDeltaFromRuntimeEvent() {
        let reducer = SessionStateReducer()
        var snapshot = SessionSnapshot()
        snapshot.activeTurn = TurnSnapshot(id: "t1", userMessage: nil, assistantText: "", isCompleted: false)

        let event = RuntimeEvent(
            runtime: .codex, type: .assistantDelta,
            payload: .assistantDelta(text: "Hello")
        )
        let actions = reducer.actions(from: event)
        for action in actions { reducer.reduce(&snapshot, action: action) }

        XCTAssertEqual(snapshot.activeTurn?.assistantText, "Hello")
    }

    func test_reducer_turnCompletedFromRuntimeEvent() {
        let reducer = SessionStateReducer()
        var snapshot = SessionSnapshot()
        snapshot.activeTurn = TurnSnapshot(id: "t1", userMessage: "fix", assistantText: "done", isCompleted: false)

        let event = RuntimeEvent(
            runtime: .codex, type: .turnCompleted,
            payload: .turnCompleted(turnID: "t1")
        )
        let actions = reducer.actions(from: event)
        for action in actions { reducer.reduce(&snapshot, action: action) }

        XCTAssertTrue(snapshot.activeTurn?.isCompleted == true)
        XCTAssertEqual(snapshot.status, .completed)
    }

    func test_reducer_approvalRequestedFromRuntimeEvent() {
        let reducer = SessionStateReducer()
        var snapshot = SessionSnapshot()

        let event = RuntimeEvent(
            runtime: .codex, type: .approvalRequested,
            payload: .approvalRequested(requestID: 42, tool: "run_shell_command", command: "swift test", riskLevel: "high")
        )
        let actions = reducer.actions(from: event)
        for action in actions { reducer.reduce(&snapshot, action: action) }

        XCTAssertNotNil(snapshot.pendingApprovals["42"])
        XCTAssertEqual(snapshot.pendingApprovals["42"]?.isPending, true)
        XCTAssertEqual(snapshot.status, .waitingOnApproval)
    }

    func test_reducer_approvalResolvedFromRuntimeEvent() {
        let reducer = SessionStateReducer()
        var snapshot = SessionSnapshot()
        snapshot.pendingApprovals["42"] = ApprovalSnapshot(
            requestID: 42, method: "run", title: "run", reason: nil,
            command: nil, decision: nil, isPending: true
        )
        snapshot.status = .waitingOnApproval

        let event = RuntimeEvent(
            runtime: .codex, type: .approvalResolved,
            payload: .approvalResolved(requestID: 42, decision: "accept")
        )
        let actions = reducer.actions(from: event)
        for action in actions { reducer.reduce(&snapshot, action: action) }

        XCTAssertEqual(snapshot.pendingApprovals["42"]?.decision, "accept")
        XCTAssertEqual(snapshot.pendingApprovals["42"]?.isPending, false)
        XCTAssertEqual(snapshot.status, .active)
    }

    func test_reducer_errorFromRuntimeEvent() {
        let reducer = SessionStateReducer()
        var snapshot = SessionSnapshot()

        let event = RuntimeEvent(
            runtime: .claudeCode, type: .error,
            payload: .error(message: "timeout", code: "ETIMEDOUT")
        )
        let actions = reducer.actions(from: event)
        for action in actions { reducer.reduce(&snapshot, action: action) }

        XCTAssertEqual(snapshot.lastError?.message, "timeout")
        XCTAssertEqual(snapshot.status, .systemError)
    }

    func test_reducer_exitedFromRuntimeEvent() {
        let reducer = SessionStateReducer()
        var snapshot = SessionSnapshot()

        let event = RuntimeEvent(
            runtime: .codex, type: .exited,
            payload: .exited(code: 1)
        )
        let actions = reducer.actions(from: event)
        for action in actions { reducer.reduce(&snapshot, action: action) }

        XCTAssertTrue(snapshot.hasExited)
        XCTAssertEqual(snapshot.status, .exited)
    }

    func test_reducer_unknownEventProducesNoActions() {
        let reducer = SessionStateReducer()
        let event = RuntimeEvent(
            runtime: .codex, type: .unknown,
            payload: .generic(method: "future/event", params: nil)
        )
        XCTAssertTrue(reducer.actions(from: event).isEmpty)
    }

    // MARK: - Full Pipeline: CodexEvent → Adapter → Reducer → Snapshot

    func test_fullPipeline_codexEventToSnapshot() {
        let adapter = CodexRuntimeAdapter()
        let reducer = SessionStateReducer()
        var snapshot = SessionSnapshot()

        // 1. thread/started
        let events1 = adapter.adapt(
            .notification(method: "thread/started", params: ["id": "t1", "cwd": "/tmp"]),
            sessionID: nil
        )
        for event in events1 {
            for action in reducer.actions(from: event) { reducer.reduce(&snapshot, action: action) }
        }
        XCTAssertEqual(snapshot.threadID, "t1")

        // 2. turn/started
        let events2 = adapter.adapt(
            .notification(method: "turn/started", params: ["turn_id": "turn-1", "input": "fix login"]),
            sessionID: "t1"
        )
        for event in events2 {
            for action in reducer.actions(from: event) { reducer.reduce(&snapshot, action: action) }
        }
        XCTAssertEqual(snapshot.activeTurn?.id, "turn-1")
        XCTAssertEqual(snapshot.activeTurn?.userMessage, "fix login")

        // 3. assistant delta
        let events3 = adapter.adapt(
            .notification(method: "item/agentMessage/delta", params: ["delta": "I'll fix it"]),
            sessionID: "t1"
        )
        for event in events3 {
            for action in reducer.actions(from: event) { reducer.reduce(&snapshot, action: action) }
        }
        XCTAssertEqual(snapshot.activeTurn?.assistantText, "I'll fix it")

        // 4. turn/completed
        let events4 = adapter.adapt(
            .notification(method: "turn/completed", params: ["turn_id": "turn-1"]),
            sessionID: "t1"
        )
        for event in events4 {
            for action in reducer.actions(from: event) { reducer.reduce(&snapshot, action: action) }
        }
        XCTAssertTrue(snapshot.activeTurn?.isCompleted == true)
        XCTAssertEqual(snapshot.status, .completed)
    }

    // MARK: - MacRelayService Integration

    func test_ingestWithRuntimeEvent_producesBothEventTypes() throws {
        let service = MacRelayService()
        let event = CodexAppServerEvent.notification(
            method: "turn/started",
            params: ["turn_id": "turn-1", "input": "test"]
        )

        let (relayEvents, runtimeEvents) = try service.ingestWithRuntimeEvent(
            event, runtime: .codex, sessionID: "sess-1"
        )

        XCTAssertFalse(relayEvents.isEmpty)
        XCTAssertFalse(runtimeEvents.isEmpty)
        XCTAssertEqual(runtimeEvents[0].type, .turnStarted)
        XCTAssertNotNil(runtimeEvents[0].seq)
        XCTAssertEqual(service.runtimeEvents.count, 1)
    }

    // MARK: - Version Compatibility

    func test_versionFieldDefaultsTo1() {
        let event = RuntimeEvent(
            runtime: .codex, type: .sessionStarted,
            payload: .sessionStarted(sessionID: "s1", cwd: nil)
        )
        XCTAssertEqual(event.version, 1)
    }
}
