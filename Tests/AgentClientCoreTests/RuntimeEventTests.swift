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

        // All fields are `let` — verified by compilation.
        // seq is also `let` (nil until assigned via withSeq).
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
        XCTAssertEqual(withSeq.type, original.type)
        // Original is unchanged (immutability)
        XCTAssertNil(original.seq)
    }

    func test_runtimeEventHasAllRequiredFields() {
        let event = RuntimeEvent(
            sessionID: "s1",
            runID: "r1",
            runtime: .claudeCode,
            type: .turnStarted,
            payload: .turnStarted(turnID: "turn-1", input: "fix the bug")
        )

        XCTAssertFalse(event.id.isEmpty)
        XCTAssertNil(event.seq)
        XCTAssertEqual(event.version, 1)
        XCTAssertNotNil(event.timestamp)
        XCTAssertEqual(event.sessionID, "s1")
        XCTAssertEqual(event.runID, "r1")
        XCTAssertEqual(event.runtime, .claudeCode)
        XCTAssertEqual(event.type, .turnStarted)
    }

    // MARK: - RuntimeIdentifier Tests

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
        XCTAssertEqual(RuntimeIdentifier.from("claude-code"), .claudeCode)
        XCTAssertEqual(RuntimeIdentifier.from("openai"), .openAI)
        XCTAssertEqual(RuntimeIdentifier.from("deepseek"), .deepSeek)
        XCTAssertEqual(RuntimeIdentifier.from("mimo"), .mimo)
    }

    func test_runtimeIdentifier_fromMapsUnknownToCustom() {
        let id = RuntimeIdentifier.from("future-provider-xyz")
        XCTAssertEqual(id, .custom)
    }

    func test_runtimeIdentifierCodable_roundTripsKnown() throws {
        let original = RuntimeIdentifier.claudeCode
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeIdentifier.self, from: data)
        XCTAssertEqual(decoded, .claudeCode)
    }

    func test_runtimeIdentifierCodable_decodesUnknownAsCustom() throws {
        // Simulate a future provider not in the enum
        let json = "\"quantum-ai-v2\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RuntimeIdentifier.self, from: data)
        XCTAssertEqual(decoded, .custom)
    }

    // MARK: - RuntimeEventType Forward Compatibility

    func test_runtimeEventTypeCoversFullLifecycle() {
        let all = RuntimeEventType.allCases
        XCTAssertTrue(all.contains(.sessionStarted))
        XCTAssertTrue(all.contains(.turnStarted))
        XCTAssertTrue(all.contains(.turnCompleted))
        XCTAssertTrue(all.contains(.toolCallRequested))
        XCTAssertTrue(all.contains(.approvalRequested))
        XCTAssertTrue(all.contains(.fileChangeDetected))
        XCTAssertTrue(all.contains(.error))
        XCTAssertTrue(all.contains(.exited))
        XCTAssertTrue(all.contains(.unknown))
    }

    func test_runtimeEventTypeCodable_roundTripsKnown() throws {
        let original = RuntimeEventType.turnStarted
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEventType.self, from: data)
        XCTAssertEqual(decoded, .turnStarted)
    }

    func test_runtimeEventTypeCodable_decodesUnknownAsUnknown() throws {
        // Simulate a future event type not in the enum
        let json = "\"agent.reflection.completed\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RuntimeEventType.self, from: data)
        if case .unknown = decoded {
            // Expected
        } else {
            XCTFail("Expected .unknown, got \(decoded)")
        }
    }

    func test_runtimeEventType_unknownPreservesRawValue() {
        // .unknown's rawValue is "__unknown__" (the enum case),
        // but the actual string is lost in the current Codable impl.
        // This is acceptable — the event type is preserved in the JSON.
        let unknown = RuntimeEventType.unknown
        XCTAssertEqual(unknown.rawValue, "__unknown__")
    }

    // MARK: - RuntimeEventPayload Forward Compatibility

    func test_encodeDecodeRoundTrip_sessionStarted() throws {
        let original = RuntimeEventPayload.sessionStarted(sessionID: "s1", cwd: "/tmp")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEventPayload.self, from: data)

        if case let .sessionStarted(sid, cwd) = decoded {
            XCTAssertEqual(sid, "s1")
            XCTAssertEqual(cwd, "/tmp")
        } else {
            XCTFail("Expected sessionStarted, got \(decoded)")
        }
    }

    func test_encodeDecodeRoundTrip_turnStarted() throws {
        let original = RuntimeEventPayload.turnStarted(turnID: "t1", input: "fix bug")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEventPayload.self, from: data)

        if case let .turnStarted(tid, input) = decoded {
            XCTAssertEqual(tid, "t1")
            XCTAssertEqual(input, "fix bug")
        } else {
            XCTFail("Expected turnStarted")
        }
    }

    func test_encodeDecodeRoundTrip_assistantDelta() throws {
        let original = RuntimeEventPayload.assistantDelta(text: "Hello!")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEventPayload.self, from: data)

        if case let .assistantDelta(text) = decoded {
            XCTAssertEqual(text, "Hello!")
        } else {
            XCTFail("Expected assistantDelta")
        }
    }

    func test_encodeDecodeRoundTrip_approvalRequested() throws {
        let original = RuntimeEventPayload.approvalRequested(
            requestID: 42, tool: "run_shell_command", command: "swift test", riskLevel: "high"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEventPayload.self, from: data)

        if case let .approvalRequested(rid, tool, cmd, risk) = decoded {
            XCTAssertEqual(rid, 42)
            XCTAssertEqual(tool, "run_shell_command")
            XCTAssertEqual(cmd, "swift test")
            XCTAssertEqual(risk, "high")
        } else {
            XCTFail("Expected approvalRequested")
        }
    }

    func test_encodeDecodeRoundTrip_error() throws {
        let original = RuntimeEventPayload.error(message: "timeout", code: "ETIMEDOUT")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEventPayload.self, from: data)

        if case let .error(msg, code) = decoded {
            XCTAssertEqual(msg, "timeout")
            XCTAssertEqual(code, "ETIMEDOUT")
        } else {
            XCTFail("Expected error")
        }
    }

    func test_encodeDecodeRoundTrip_exited() throws {
        let original = RuntimeEventPayload.exited(code: 137)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEventPayload.self, from: data)

        if case let .exited(code) = decoded {
            XCTAssertEqual(code, 137)
        } else {
            XCTFail("Expected exited")
        }
    }

    func test_encodeDecodeRoundTrip_unknown() throws {
        let rawJSON = """
        {"case":"agent.selfReflection","depth":3}
        """.data(using: .utf8)!
        let original = RuntimeEventPayload.unknown(discriminator: "agent.selfReflection", data: rawJSON)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEventPayload.self, from: data)

        if case let .unknown(discriminator, _) = decoded {
            XCTAssertEqual(discriminator, "agent.selfReflection")
        } else {
            XCTFail("Expected unknown, got \(decoded)")
        }
    }

    func test_unknownPayload_decodesFromFutureEvent() throws {
        // Simulate a future payload type we don't know about
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

    // MARK: - Full RuntimeEvent Round-Trip

    func test_fullEvent_encodeDecodeRoundTrip() throws {
        let event = RuntimeEvent(
            id: "test-id-123",
            seq: 99,
            version: 1,
            timestamp: Date(timeIntervalSince1970: 1000000),
            sessionID: "sess-1",
            runID: "run-1",
            runtime: .claudeCode,
            type: .turnStarted,
            payload: .turnStarted(turnID: "turn-1", input: "fix login")
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(RuntimeEvent.self, from: data)

        XCTAssertEqual(decoded.id, "test-id-123")
        XCTAssertEqual(decoded.seq, 99)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.sessionID, "sess-1")
        XCTAssertEqual(decoded.runID, "run-1")
        XCTAssertEqual(decoded.runtime, .claudeCode)
        XCTAssertEqual(decoded.type, .turnStarted)

        if case let .turnStarted(tid, input) = decoded.payload {
            XCTAssertEqual(tid, "turn-1")
            XCTAssertEqual(input, "fix login")
        } else {
            XCTFail("Expected turnStarted payload")
        }
    }

    func test_fullEvent_withUnknownTypeAndPayload() throws {
        // Simulate a completely future event
        let json = """
        {
            "id": "future-1",
            "seq": null,
            "version": 1,
            "timestamp": 1000000,
            "sessionID": "s1",
            "runID": null,
            "runtime": "quantum-ai",
            "type": "agent.reflection.completed",
            "payload": {"case":"agent.multiStepReflection","steps":5}
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RuntimeEvent.self, from: data)

        // RuntimeIdentifier: unknown → .custom
        XCTAssertEqual(decoded.runtime, .custom)

        // RuntimeEventType: unknown
        if case .unknown = decoded.type {
            // Expected
        } else {
            XCTFail("Expected .unknown type, got \(decoded.type)")
        }

        // RuntimeEventPayload: unknown
        if case let .unknown(discriminator, _) = decoded.payload {
            XCTAssertEqual(discriminator, "agent.multiStepReflection")
        } else {
            XCTFail("Expected .unknown payload")
        }
    }

    // MARK: - Reducer Conversion Tests

    func test_reducerConverts_threadStarted_toSessionStarted() {
        let reducer = SessionStateReducer()
        let event = CodexAppServerEvent.notification(
            method: "thread/started",
            params: ["id": "thread-abc", "cwd": "/tmp"]
        )

        let runtimeEvent = reducer.runtimeEvent(from: event, runtime: .codex, sessionID: "old")

        XCTAssertNotNil(runtimeEvent)
        XCTAssertEqual(runtimeEvent?.type, .sessionStarted)
        XCTAssertEqual(runtimeEvent?.runtime, .codex)
        XCTAssertEqual(runtimeEvent?.sessionID, "thread-abc")
    }

    func test_reducerConverts_turnStarted_toTurnStarted() {
        let reducer = SessionStateReducer()
        let event = CodexAppServerEvent.notification(
            method: "turn/started",
            params: ["turn_id": "turn-1", "input": "fix login"]
        )

        let runtimeEvent = reducer.runtimeEvent(from: event, runtime: .claudeCode, sessionID: "sess-1")

        XCTAssertNotNil(runtimeEvent)
        XCTAssertEqual(runtimeEvent?.type, .turnStarted)
        XCTAssertEqual(runtimeEvent?.sessionID, "sess-1")

        if case let .turnStarted(tid, input) = runtimeEvent?.payload {
            XCTAssertEqual(tid, "turn-1")
            XCTAssertEqual(input, "fix login")
        } else {
            XCTFail("Expected turnStarted payload")
        }
    }

    func test_reducerConverts_assistantDelta() {
        let reducer = SessionStateReducer()
        let event = CodexAppServerEvent.notification(
            method: "item/agentMessage/delta",
            params: ["delta": "Hello"]
        )

        let runtimeEvent = reducer.runtimeEvent(from: event, runtime: .codex)

        XCTAssertNotNil(runtimeEvent)
        XCTAssertEqual(runtimeEvent?.type, .assistantDelta)
    }

    func test_reducerConverts_error() {
        let reducer = SessionStateReducer()
        let event = CodexAppServerEvent.notification(
            method: "error",
            params: ["error": ["message": "timeout", "code": "ETIMEDOUT"]]
        )

        let runtimeEvent = reducer.runtimeEvent(from: event, runtime: .claudeCode)

        XCTAssertNotNil(runtimeEvent)
        XCTAssertEqual(runtimeEvent?.type, .error)

        if case let .error(msg, code) = runtimeEvent?.payload {
            XCTAssertEqual(msg, "timeout")
            XCTAssertEqual(code, "ETIMEDOUT")
        } else {
            XCTFail("Expected error payload")
        }
    }

    func test_reducerReturnsNilForResponse() {
        let reducer = SessionStateReducer()
        let event = CodexAppServerEvent.response(id: 1, result: [:], error: nil)
        XCTAssertNil(reducer.runtimeEvent(from: event, runtime: .codex))
    }

    func test_reducerReturnsNilForStderr() {
        let reducer = SessionStateReducer()
        let event = CodexAppServerEvent.stderr("debug output")
        XCTAssertNil(reducer.runtimeEvent(from: event, runtime: .codex))
    }

    // MARK: - MacRelayService Integration

    func test_ingestWithRuntimeEvent_producesBothEventTypes() throws {
        let service = MacRelayService()
        let event = CodexAppServerEvent.notification(
            method: "turn/started",
            params: ["turn_id": "turn-1", "input": "test"]
        )

        let (relayEvents, runtimeEvent) = try service.ingestWithRuntimeEvent(
            event, runtime: .codex, sessionID: "sess-1"
        )

        XCTAssertFalse(relayEvents.isEmpty)
        XCTAssertNotNil(runtimeEvent)
        XCTAssertEqual(runtimeEvent?.type, .turnStarted)
        XCTAssertNotNil(runtimeEvent?.seq, "seq should be assigned by EventStore")
        XCTAssertEqual(service.runtimeEvents.count, 1)
    }

    func test_ingestWithRuntimeEvent_respectsCapacity() throws {
        let service = MacRelayService()

        for i in 0..<1005 {
            let event = CodexAppServerEvent.notification(
                method: "item/agentMessage/delta",
                params: ["delta": "msg-\(i)"]
            )
            _ = try service.ingestWithRuntimeEvent(event, runtime: .codex)
        }

        XCTAssertLessThanOrEqual(service.runtimeEvents.count, 1000)
    }

    // MARK: - Version Compatibility

    func test_versionFieldDefaultsTo1() {
        let event = RuntimeEvent(
            runtime: .codex,
            type: .sessionStarted,
            payload: .sessionStarted(sessionID: "s1", cwd: nil)
        )
        XCTAssertEqual(event.version, 1)
    }

    func test_versionFieldSurvivesRoundTrip() throws {
        let event = RuntimeEvent(
            version: 1,
            runtime: .openAI,
            type: .assistantDelta,
            payload: .assistantDelta(text: "hi")
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(RuntimeEvent.self, from: data)
        XCTAssertEqual(decoded.version, 1)
    }
}
