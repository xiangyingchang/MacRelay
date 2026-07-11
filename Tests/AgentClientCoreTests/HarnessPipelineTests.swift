import XCTest
@testable import AgentClientCore

/// End-to-end pipeline tests for the RuntimeEvent harness.
///
/// These tests verify the complete chain:
///   Fixture → TraceWriter → ReadBack → Reducer → Snapshot → Timeline
///
/// Each test loads a fixture JSONL file, runs it through the pipeline,
/// and verifies intermediate and final state at every stage.
final class HarnessPipelineTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarnessPipelineTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Trace Replay

    /// Load fixture → write to TraceWriter → read back → verify all events preserved.
    func testTraceReplay_normalCodingRun() throws {
        let original = try FixtureLoader.loadFixture("normal_coding_run")
        let writer = TraceWriter(runID: "replay-test", baseDirectory: tempDir)

        // Write all fixture events
        for (i, event) in original.enumerated() {
            let withSeq = event.withSeq(UInt64(i + 1))
            try writer.append(withSeq)
        }
        XCTAssertEqual(writer.count, original.count)

        // Read back
        let readBack = try writer.readAll()
        XCTAssertEqual(readBack.count, original.count)

        // Verify every event round-trips
        for (orig, read) in zip(original, readBack) {
            XCTAssertEqual(orig.id, read.id, "Event ID mismatch")
            XCTAssertEqual(orig.type, read.type, "Event type mismatch for \(orig.id)")
            XCTAssertEqual(orig.runtime, read.runtime, "Runtime mismatch for \(orig.id)")
            XCTAssertEqual(orig.sessionID, read.sessionID, "SessionID mismatch for \(orig.id)")
            XCTAssertEqual(orig.payload, read.payload, "Payload mismatch for \(orig.id)")
        }
    }

    /// Verify TraceWriter read(afterSeq:) works with fixture data.
    func testTraceReplay_afterSeqFiltering() throws {
        let original = try FixtureLoader.loadFixture("approval_rejected")
        let writer = TraceWriter(runID: "seq-filter", baseDirectory: tempDir)

        for (i, event) in original.enumerated() {
            try writer.append(event.withSeq(UInt64(i + 1)))
        }

        // Read after seq 3 — should skip first 3 events
        let after3 = try writer.read(afterSeq: 3)
        XCTAssertEqual(after3.count, original.count - 3)
        XCTAssertEqual(after3.first?.seq, 4)
    }

    // MARK: - Reducer Rebuild

    /// Load fixture → reduce to snapshot → verify final state.
    func testReducerRebuild_normalCodingRun() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")
        let snapshot = FixtureLoader.reduceToSnapshot(events)

        // Session was started
        XCTAssertEqual(snapshot.threadID, "session-001")
        XCTAssertNotNil(snapshot.cwd)

        // Turn completed successfully
        XCTAssertEqual(snapshot.status, .completed)
        XCTAssertFalse(snapshot.completedTurns.isEmpty)
        let lastTurn = snapshot.completedTurns.last
        XCTAssertEqual(lastTurn?.id, "turn-001")
        XCTAssertTrue(lastTurn?.isCompleted ?? false)

        // User message captured
        XCTAssertEqual(lastTurn?.userMessage, "修复登录页面的崩溃问题")

        // File changes recorded
        XCTAssertFalse(snapshot.fileChanges.isEmpty)

        // No errors
        XCTAssertNil(snapshot.lastError)
    }

    /// Load approval fixture → reduce → verify approval state.
    func testReducerRebuild_approvalRejected() throws {
        let events = try FixtureLoader.loadFixture("approval_rejected")
        let snapshot = FixtureLoader.reduceToSnapshot(events)

        XCTAssertEqual(snapshot.threadID, "session-002")

        // Approval was requested and rejected
        let approval = snapshot.pendingApprovals.values.first
        XCTAssertNotNil(approval)
        XCTAssertEqual(approval?.decision, "reject")
        XCTAssertFalse(approval?.isPending ?? true)

        // Error from rejection
        XCTAssertNotNil(snapshot.lastError)
        XCTAssertTrue(snapshot.lastError?.message.contains("用户拒绝") ?? false)
    }

    /// Load tool failure fixture → reduce → verify error state.
    func testReducerRebuild_toolFailed() throws {
        let events = try FixtureLoader.loadFixture("tool_failed")
        let snapshot = FixtureLoader.reduceToSnapshot(events)

        XCTAssertEqual(snapshot.threadID, "session-003")

        // Error recorded
        XCTAssertNotNil(snapshot.lastError)
        XCTAssertTrue(snapshot.lastError?.message.contains("Test target failed") ?? false)
        XCTAssertEqual(snapshot.lastError?.code, "TEST_FAILURE")

        // Turn still completed
        XCTAssertFalse(snapshot.completedTurns.isEmpty)
        let lastTurn = snapshot.completedTurns.last
        XCTAssertEqual(lastTurn?.id, "turn-003")
    }

    // MARK: - Timeline Build

    /// Load fixture → build timeline → verify items.
    func testTimelineBuild_normalCodingRun() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")
        let timeline = TimelineBuilder().build(from: events)

        // Should have at least user message + assistant message + final result
        XCTAssertGreaterThanOrEqual(timeline.count, 3)

        // First item should be user message
        XCTAssertEqual(timeline.first?.type, .userMessage)

        // Last item should be final result
        XCTAssertEqual(timeline.last?.type, .finalResult)

        // Should have tool calls
        let toolCalls = timeline.filter { $0.type == .toolCall }
        XCTAssertGreaterThan(toolCalls.count, 0)
    }

    /// Load approval fixture → build timeline → verify approval items.
    func testTimelineBuild_approvalRejected() throws {
        let events = try FixtureLoader.loadFixture("approval_rejected")
        let timeline = TimelineBuilder().build(from: events)

        // Should have approval items
        let approvals = timeline.filter { $0.type == .approval }
        XCTAssertGreaterThanOrEqual(approvals.count, 1, "Should have at least one approval item")

        // Should have error item
        let errors = timeline.filter { $0.type == .error }
        XCTAssertGreaterThanOrEqual(errors.count, 1, "Should have at least one error item")
    }

    /// Load tool failure fixture → build timeline → verify error item.
    func testTimelineBuild_toolFailed() throws {
        let events = try FixtureLoader.loadFixture("tool_failed")
        let timeline = TimelineBuilder().build(from: events)

        // Should have at least user message + error
        XCTAssertGreaterThanOrEqual(timeline.count, 2)

        // Should have tool call items
        let toolCalls = timeline.filter { $0.type == .toolCall }
        XCTAssertGreaterThan(toolCalls.count, 0)
    }

    // MARK: - Full Pipeline: Fixture → Trace → ReadBack → Reducer → Timeline

    /// The definitive end-to-end test: load fixture, persist to trace,
    /// read back, reduce to snapshot, build timeline — every stage verified.
    func testFullPipeline_normalCodingRun() throws {
        // Stage 1: Load fixture
        let original = try FixtureLoader.loadFixture("normal_coding_run")
        XCTAssertEqual(original.count, 15)

        // Stage 2: Write to TraceWriter
        let writer = TraceWriter(runID: "full-pipeline", baseDirectory: tempDir)
        for (i, event) in original.enumerated() {
            try writer.append(event.withSeq(UInt64(i + 1)))
        }

        // Stage 3: Read back from trace
        let readBack = try writer.readAll()
        XCTAssertEqual(readBack.count, original.count)

        // Stage 4: Reduce to snapshot
        let snapshot = FixtureLoader.reduceToSnapshot(readBack)
        XCTAssertEqual(snapshot.threadID, "session-001")
        XCTAssertEqual(snapshot.status, .completed)
        XCTAssertFalse(snapshot.completedTurns.isEmpty)
        XCTAssertNil(snapshot.lastError)

        // Stage 5: Build timeline from read-back events
        let timeline = TimelineBuilder().build(from: readBack)
        XCTAssertGreaterThanOrEqual(timeline.count, 3)

        // Verify timeline has user message, assistant message, and final result
        let userMessages = timeline.filter { $0.type == .userMessage }
        XCTAssertFalse(userMessages.isEmpty, "Timeline should have user messages")

        let assistantMessages = timeline.filter { $0.type == .assistantMessage }
        XCTAssertFalse(assistantMessages.isEmpty, "Timeline should have assistant messages")

        let finalResults = timeline.filter { $0.type == .finalResult }
        XCTAssertFalse(finalResults.isEmpty, "Timeline should have final results")
    }

    /// Full pipeline for approval flow.
    func testFullPipeline_approvalRejected() throws {
        let original = try FixtureLoader.loadFixture("approval_rejected")

        let writer = TraceWriter(runID: "approval-pipeline", baseDirectory: tempDir)
        for (i, event) in original.enumerated() {
            try writer.append(event.withSeq(UInt64(i + 1)))
        }

        let readBack = try writer.readAll()
        XCTAssertEqual(readBack.count, original.count)

        // Snapshot shows rejection
        let snapshot = FixtureLoader.reduceToSnapshot(readBack)
        XCTAssertEqual(snapshot.threadID, "session-002")
        XCTAssertNotNil(snapshot.lastError)

        // Timeline shows approval + error
        let timeline = TimelineBuilder().build(from: readBack)
        let approvals = timeline.filter { $0.type == .approval }
        XCTAssertGreaterThanOrEqual(approvals.count, 1)

        let errors = timeline.filter { $0.type == .error }
        XCTAssertGreaterThanOrEqual(errors.count, 1)
    }

    /// Full pipeline for tool failure.
    func testFullPipeline_toolFailed() throws {
        let original = try FixtureLoader.loadFixture("tool_failed")

        let writer = TraceWriter(runID: "toolfail-pipeline", baseDirectory: tempDir)
        for (i, event) in original.enumerated() {
            try writer.append(event.withSeq(UInt64(i + 1)))
        }

        let readBack = try writer.readAll()
        XCTAssertEqual(readBack.count, original.count)

        // Snapshot shows error
        let snapshot = FixtureLoader.reduceToSnapshot(readBack)
        XCTAssertNotNil(snapshot.lastError)
        XCTAssertTrue(snapshot.lastError?.message.contains("Test target failed") ?? false)

        // Timeline has tool call + error
        let timeline = TimelineBuilder().build(from: readBack)
        let toolCalls = timeline.filter { $0.type == .toolCall }
        XCTAssertGreaterThan(toolCalls.count, 0)
    }

    // MARK: - EventStore Replay

    /// Load fixture → ingest through MacRelayService → verify EventStore replay.
    func testEventStoreReplay_normalCodingRun() throws {
        let service = MacRelayService()
        let events = try FixtureLoader.loadFixture("normal_coding_run")

        // Ingest each event through the service
        for event in events {
            let codexEvent = Self.eventToCodexEvent(event)
            _ = try service.ingest(codexEvent)
        }

        // Verify EventStore has events
        XCTAssertGreaterThan(service.eventCount, 0)

        // Replay from beginning
        let replay = service.replay(afterSeq: 0)
        if case let .events(stored) = replay {
            XCTAssertGreaterThan(stored.count, 0)
            // Verify events are in order
            for i in 1..<stored.count {
                XCTAssertGreaterThanOrEqual(stored[i].seq, stored[i-1].seq)
            }
        } else {
            XCTFail("Expected events in replay")
        }

        // Snapshot reflects final state
        XCTAssertEqual(service.snapshot.threadID, "session-001")
        XCTAssertEqual(service.snapshot.status, .completed)
    }

    // MARK: - Crash Recovery

    /// Simulate crash: write events, deallocate writer, create new writer, verify data.
    func testCrashRecovery_normalCodingRun() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")

        // Write with first writer
        do {
            let writer = TraceWriter(runID: "crash-recovery", baseDirectory: tempDir)
            for (i, event) in events.enumerated() {
                try writer.append(event.withSeq(UInt64(i + 1)))
            }
        }

        // New writer simulates app restart
        let writer2 = TraceWriter(runID: "crash-recovery", baseDirectory: tempDir)
        let readBack = try writer2.readAll()
        XCTAssertEqual(readBack.count, events.count)

        // Can still reduce to snapshot
        let snapshot = FixtureLoader.reduceToSnapshot(readBack)
        XCTAssertEqual(snapshot.threadID, "session-001")
        XCTAssertEqual(snapshot.status, .completed)
    }

    // MARK: - Fixture Schema Contract

    /// Verify all fixtures have consistent schema: every event has required fields.
    func testFixtureSchemaContract() throws {
        let names = ["normal_coding_run", "approval_rejected", "tool_failed"]

        for name in names {
            let events = try FixtureLoader.loadFixture(name)

            for event in events {
                // Required fields
                XCTAssertFalse(event.id.isEmpty, "[\(name)] Event missing ID")
                XCTAssertGreaterThanOrEqual(event.version, 1, "[\(name)] Event \(event.id) has version < 1")
                XCTAssertNotNil(event.sessionID, "[\(name)] Event \(event.id) missing sessionID")

                // Payload must not be .unknown for known event types
                if event.type != .unknown {
                    if case .unknown = event.payload {
                        XCTFail("[\(name)] Event \(event.id) has type \(event.type) but unknown payload")
                    }
                }
            }
        }
    }

    /// Verify fixture event counts match expected values.
    func testFixtureEventCounts() throws {
        let expected: [(String, Int)] = [
            ("normal_coding_run", 15),
            ("approval_rejected", 7),
            ("tool_failed", 7),
        ]

        for (name, count) in expected {
            let events = try FixtureLoader.loadFixture(name)
            XCTAssertEqual(events.count, count, "Fixture '\(name)' should have \(count) events")
        }
    }

    // MARK: - Helpers

    private static func eventToCodexEvent(_ event: RuntimeEvent) -> CodexAppServerEvent {
        switch event.type {
        case .sessionStarted:
            if case let .sessionStarted(sessionID, cwd) = event.payload {
                var params: [String: Any] = ["id": sessionID]
                if let cwd { params["cwd"] = cwd }
                params["status"] = ["type": "active"]
                return .notification(method: "thread/started", params: params)
            }
            return .raw("")
        case .turnStarted:
            if case let .turnStarted(turnID, input) = event.payload {
                var params: [String: Any] = [:]
                if let turnID { params["turn_id"] = turnID }
                if let input { params["input"] = input }
                return .notification(method: "turn/started", params: params)
            }
            return .raw("")
        case .assistantDelta:
            if case let .assistantDelta(text) = event.payload {
                return .notification(method: "item/agentMessage/delta", params: ["delta": text])
            }
            return .raw("")
        case .turnCompleted:
            if case let .turnCompleted(turnID) = event.payload {
                var params: [String: Any] = [:]
                if let turnID { params["turn_id"] = turnID }
                return .notification(method: "turn/completed", params: params)
            }
            return .raw("")
        case .approvalRequested:
            if case let .approvalRequested(requestID, tool, command, _) = event.payload {
                var params: [String: Any] = [:]
                if let command { params["command"] = command }
                return .serverRequest(id: requestID, method: "requestApproval_\(tool)", params: params)
            }
            return .raw("")
        case .approvalResolved:
            if case let .approvalResolved(requestID, decision) = event.payload {
                return .serverRequest(id: requestID, method: "approval.resolve", params: ["decision": decision])
            }
            return .raw("")
        case .fileChangeDetected:
            if case let .fileChange(path, changeKind) = event.payload {
                let item: [String: Any] = [
                    "type": "fileChange", "path": path,
                    "kind": changeKind, "status": changeKind,
                ]
                return .notification(method: "item/completed", params: ["item": item])
            }
            return .raw("")
        case .diffUpdated:
            if case let .diffUpdated(files) = event.payload {
                return .notification(method: "diff.updated", params: ["changedFiles": files])
            }
            return .raw("")
        case .error:
            if case let .error(message, code) = event.payload {
                var errorDict: [String: Any] = ["message": message]
                if let code { errorDict["codexErrorInfo"] = code }
                return .notification(method: "error", params: ["error": errorDict])
            }
            return .raw("")
        case .turnError:
            if case let .turnError(_, message) = event.payload {
                return .notification(method: "error", params: ["error": ["message": message]])
            }
            return .raw("")
        case .exited:
            #if os(macOS)
            return .exit(code: 0, reason: .exit)
            #else
            return .raw("")
            #endif
        default:
            return .raw("")
        }
    }
}
