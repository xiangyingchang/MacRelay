import XCTest
@testable import AgentClientCore

// MARK: - RuntimeEvent v1 Tests

@MainActor
final class RuntimeEventTests: XCTestCase {

    // MARK: - Schema Tests

    func test_runtimeEventHasAllRequiredFields() {
        let event = RuntimeEvent(
            runtime: .claudeCode,
            type: .turnStarted,
            payload: .turnStarted(turnID: "turn-1", input: "fix the bug")
        )

        XCTAssertFalse(event.id.isEmpty)
        XCTAssertNil(event.seq) // assigned by EventStore
        XCTAssertEqual(event.version, 1)
        XCTAssertNotNil(event.timestamp)
        XCTAssertEqual(event.runtime, .claudeCode)
        XCTAssertEqual(event.type, .turnStarted)
    }

    func test_runtimeIdentifierCoversAllRuntimes() {
        let all = RuntimeIdentifier.allCases
        XCTAssertTrue(all.contains(.codex))
        XCTAssertTrue(all.contains(.claudeCode))
        XCTAssertTrue(all.contains(.api))
    }

    func test_runtimeEventTypeCoversFullLifecycle() {
        let all = RuntimeEventType.allCases
        // Session
        XCTAssertTrue(all.contains(.sessionStarted))
        XCTAssertTrue(all.contains(.sessionStopped))
        // Turn
        XCTAssertTrue(all.contains(.turnStarted))
        XCTAssertTrue(all.contains(.turnCompleted))
        XCTAssertTrue(all.contains(.turnError))
        // Assistant
        XCTAssertTrue(all.contains(.assistantDelta))
        // Tool
        XCTAssertTrue(all.contains(.toolCallRequested))
        XCTAssertTrue(all.contains(.toolCallCompleted))
        // Approval
        XCTAssertTrue(all.contains(.approvalRequested))
        XCTAssertTrue(all.contains(.approvalResolved))
        // File
        XCTAssertTrue(all.contains(.fileChangeDetected))
        XCTAssertTrue(all.contains(.diffUpdated))
        // Error
        XCTAssertTrue(all.contains(.error))
        XCTAssertTrue(all.contains(.exited))
    }

    // MARK: - Serialization Round-Trip Tests

    func test_encodeDecodeRoundTrip_sessionStarted() throws {
        let original = RuntimeEvent(
            sessionID: "sess-1",
            runtime: .codex,
            type: .sessionStarted,
            payload: .sessionStarted(sessionID: "sess-1", cwd: "/tmp/project")
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEvent.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.runtime, .codex)
        XCTAssertEqual(decoded.type, .sessionStarted)
        XCTAssertEqual(decoded.sessionID, "sess-1")

        if case let .sessionStarted(sid, cwd) = decoded.payload {
            XCTAssertEqual(sid, "sess-1")
            XCTAssertEqual(cwd, "/tmp/project")
        } else {
            XCTFail("Expected sessionStarted payload")
        }
    }

    func test_encodeDecodeRoundTrip_assistantDelta() throws {
        let original = RuntimeEvent(
            runtime: .claudeCode,
            type: .assistantDelta,
            payload: .assistantDelta(text: "Hello, world!")
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEvent.self, from: data)

        if case let .assistantDelta(text) = decoded.payload {
            XCTAssertEqual(text, "Hello, world!")
        } else {
            XCTFail("Expected assistantDelta payload")
        }
    }

    func test_encodeDecodeRoundTrip_approvalRequested() throws {
        let original = RuntimeEvent(
            runtime: .codex,
            type: .approvalRequested,
            payload: .approvalRequested(
                requestID: 42,
                tool: "run_shell_command",
                command: "swift test",
                riskLevel: "high"
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEvent.self, from: data)

        if case let .approvalRequested(rid, tool, cmd, risk) = decoded.payload {
            XCTAssertEqual(rid, 42)
            XCTAssertEqual(tool, "run_shell_command")
            XCTAssertEqual(cmd, "swift test")
            XCTAssertEqual(risk, "high")
        } else {
            XCTFail("Expected approvalRequested payload")
        }
    }

    func test_encodeDecodeRoundTrip_error() throws {
        let original = RuntimeEvent(
            runtime: .claudeCode,
            type: .error,
            payload: .error(message: "Connection lost", code: "ECONNRESET")
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEvent.self, from: data)

        if case let .error(msg, code) = decoded.payload {
            XCTAssertEqual(msg, "Connection lost")
            XCTAssertEqual(code, "ECONNRESET")
        } else {
            XCTFail("Expected error payload")
        }
    }

    func test_encodeDecodeRoundTrip_exited() throws {
        let original = RuntimeEvent(
            runtime: .codex,
            type: .exited,
            payload: .exited(code: 1)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEvent.self, from: data)

        if case let .exited(code) = decoded.payload {
            XCTAssertEqual(code, 1)
        } else {
            XCTFail("Expected exited payload")
        }
    }

    func test_encodeDecodeRoundTrip_generic() throws {
        let original = RuntimeEvent(
            runtime: .api,
            type: .settingsUpdated,
            payload: .generic(method: "custom/event", params: ["key": "value"])
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeEvent.self, from: data)

        if case let .generic(method, params) = decoded.payload {
            XCTAssertEqual(method, "custom/event")
            XCTAssertEqual(params?["key"], "value")
        } else {
            XCTFail("Expected generic payload")
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
        // sessionID should be updated to the new thread ID
        XCTAssertEqual(runtimeEvent?.sessionID, "thread-abc")

        if case let .sessionStarted(sid, cwd) = runtimeEvent?.payload {
            XCTAssertEqual(sid, "thread-abc")
            XCTAssertEqual(cwd, "/tmp")
        } else {
            XCTFail("Expected sessionStarted payload")
        }
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

        if case let .assistantDelta(text) = runtimeEvent?.payload {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected assistantDelta payload")
        }
    }

    func test_reducerConverts_turnCompleted() {
        let reducer = SessionStateReducer()
        let event = CodexAppServerEvent.notification(
            method: "turn/completed",
            params: ["turn_id": "turn-1"]
        )

        let runtimeEvent = reducer.runtimeEvent(from: event, runtime: .codex)

        XCTAssertNotNil(runtimeEvent)
        XCTAssertEqual(runtimeEvent?.type, .turnCompleted)

        if case let .turnCompleted(tid) = runtimeEvent?.payload {
            XCTAssertEqual(tid, "turn-1")
        } else {
            XCTFail("Expected turnCompleted payload")
        }
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

    func test_reducerConverts_exit_toExited() {
        let reducer = SessionStateReducer()
        #if os(macOS)
        let event = CodexAppServerEvent.exit(code: 137, reason: .uncaughtSignal)

        let runtimeEvent = reducer.runtimeEvent(from: event, runtime: .codex)

        XCTAssertNotNil(runtimeEvent)
        XCTAssertEqual(runtimeEvent?.type, .exited)

        if case let .exited(code) = runtimeEvent?.payload {
            XCTAssertEqual(code, 137)
        } else {
            XCTFail("Expected exited payload")
        }
        #endif
    }

    func test_reducerReturnsNilForResponse() {
        let reducer = SessionStateReducer()
        let event = CodexAppServerEvent.response(id: 1, result: [:], error: nil)

        let runtimeEvent = reducer.runtimeEvent(from: event, runtime: .codex)

        XCTAssertNil(runtimeEvent, "Responses should not produce RuntimeEvents")
    }

    func test_reducerReturnsNilForStderr() {
        let reducer = SessionStateReducer()
        let event = CodexAppServerEvent.stderr("some debug output")

        let runtimeEvent = reducer.runtimeEvent(from: event, runtime: .codex)

        XCTAssertNil(runtimeEvent, "Stderr should not produce RuntimeEvents")
    }

    // MARK: - MacRelayService Integration Test

    func test_ingestWithRuntimeEvent_producesBothEventTypes() throws {
        let service = MacRelayService()
        let event = CodexAppServerEvent.notification(
            method: "turn/started",
            params: ["turn_id": "turn-1", "input": "test"]
        )

        let (relayEvents, runtimeEvent) = try service.ingestWithRuntimeEvent(
            event, runtime: .codex, sessionID: "sess-1"
        )

        // Relay events should be produced (existing pipeline)
        XCTAssertFalse(relayEvents.isEmpty, "Should produce relay events")

        // RuntimeEvent should also be produced (new pipeline)
        XCTAssertNotNil(runtimeEvent, "Should produce RuntimeEvent")
        XCTAssertEqual(runtimeEvent?.type, .turnStarted)
        XCTAssertEqual(runtimeEvent?.runtime, .codex)

        // RuntimeEvent should be stored
        XCTAssertEqual(service.runtimeEvents.count, 1)
        XCTAssertEqual(service.runtimeEvents.first?.type, .turnStarted)
    }

    func test_ingestWithRuntimeEvent_storesSeq() throws {
        let service = MacRelayService()
        let event = CodexAppServerEvent.notification(
            method: "turn/started",
            params: ["turn_id": "t1"]
        )

        let (_, runtimeEvent) = try service.ingestWithRuntimeEvent(event, runtime: .codex)

        XCTAssertNotNil(runtimeEvent?.seq, "RuntimeEvent seq should be assigned")
    }

    func test_ingestWithRuntimeEvent_respectsCapacity() throws {
        let service = MacRelayService()

        // Fill beyond capacity
        for i in 0..<1005 {
            let event = CodexAppServerEvent.notification(
                method: "item/agentMessage/delta",
                params: ["delta": "msg-\(i)"]
            )
            _ = try service.ingestWithRuntimeEvent(event, runtime: .codex)
        }

        // Should be capped at 1000
        XCTAssertLessThanOrEqual(service.runtimeEvents.count, 1000)
    }
}
