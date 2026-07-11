import XCTest
@testable import AgentClientCore

/// Tests for the enhanced timeline query service.
///
/// Covers real-time updates, historical recovery from trace,
/// consistency between real-time and historical, empty timelines,
/// and large timeline performance.
final class TimelineQueryTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimelineQueryTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeService() -> MacRelayService {
        MacRelayService()
    }

    private func codexNotification(_ method: String, params: [String: Any]) -> CodexAppServerEvent {
        .notification(method: method, params: params)
    }

    private func makeEvent(
        seq: UInt64,
        type: RuntimeEventType,
        payload: RuntimeEventPayload,
        timestamp: TimeInterval = 0,
        sessionID: String? = "session-1",
        runID: String? = "test-run",
        runtime: RuntimeIdentifier = .claudeCode
    ) -> RuntimeEvent {
        RuntimeEvent(
            id: "evt-\(seq)",
            seq: seq,
            version: 1,
            timestamp: Date(timeIntervalSince1970: timestamp > 0 ? timestamp : Double(seq)),
            sessionID: sessionID,
            runID: runID,
            runtime: runtime,
            type: type,
            payload: payload
        )
    }

    private func writeTrace(_ events: [RuntimeEvent], runID: String = "test-run") throws {
        let writer = TraceWriter(runID: runID, baseDirectory: tempDir)
        try writer.append(contentsOf: events)
    }

    // MARK: - Real-time Timeline Updates

    func testRealTimeTimelineUpdatesWhenNewEventsArrive() throws {
        let service = makeService()

        // Initially empty
        var items = service.timeline(runID: "run-1")
        XCTAssertTrue(items.isEmpty)

        // Add first event
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t1", "input": "Hello"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        items = service.timeline(runID: "run-1")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .userMessage)

        // Add streaming delta
        try service.ingestWithRuntimeEvent(
            codexNotification("item/agentMessage/delta", params: ["delta": "Hi there!"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // Delta alone doesn't produce a visible item (accumulated)
        items = service.timeline(runID: "run-1")
        XCTAssertEqual(items.count, 1)

        // Complete the turn
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/completed", params: ["turn_id": "t1"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        items = service.timeline(runID: "run-1")
        XCTAssertEqual(items.count, 3) // user + assistant + finalResult
    }

    func testRealTimeTimelineMultipleTurns() throws {
        let service = makeService()

        // Turn 1
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t1", "input": "Task 1"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/completed", params: ["turn_id": "t1"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // Turn 2
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t2", "input": "Task 2"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/completed", params: ["turn_id": "t2"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        let items = service.timeline(runID: "run-1")
        XCTAssertEqual(items.count, 4) // 2x (user + finalResult), no assistant text to flush
    }

    // MARK: - Historical Timeline from Trace

    func testHistoricalTimelineFromTrace() throws {
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .turnStarted,
                      payload: .turnStarted(turnID: "t1", input: "Fix the bug")),
            makeEvent(seq: 2, type: .assistantDelta,
                      payload: .assistantDelta(text: "I'll fix it")),
            makeEvent(seq: 3, type: .toolCallRequested,
                      payload: .toolCall(name: "read_file", params: ["path": "bug.swift"])),
            makeEvent(seq: 4, type: .toolCallCompleted,
                      payload: .toolCallCompleted(name: "read_file", result: "contents")),
            makeEvent(seq: 5, type: .turnCompleted,
                      payload: .turnCompleted(turnID: "t1")),
        ]

        try writeTrace(events)

        let service = makeService()
        let items = service.timelineFromTrace(runID: "test-run", baseDirectory: tempDir)

        XCTAssertNotNil(items)
        XCTAssertEqual(items!.count, 5) // user + toolReq + toolComplete + assistant(flushed) + finalResult
        XCTAssertEqual(items![0].type, .userMessage)
        XCTAssertEqual(items![1].type, .toolCall)      // toolCallRequested
        XCTAssertEqual(items![2].type, .toolCall)      // toolCallCompleted
        XCTAssertEqual(items![3].type, .assistantMessage) // flushed on turnCompleted
        XCTAssertEqual(items![4].type, .finalResult)
    }

    func testHistoricalTimelineReturnsNilForMissingTrace() {
        let service = makeService()
        let items = service.timelineFromTrace(runID: "nonexistent", baseDirectory: tempDir)
        XCTAssertNil(items)
    }

    func testHistoricalTimelineFromEmptyTrace() throws {
        // Write an empty file
        let dir = tempDir.appendingPathComponent("empty-run")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("trace.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let service = makeService()
        let items = service.timelineFromTrace(runID: "empty-run", baseDirectory: tempDir)

        XCTAssertNotNil(items)
        XCTAssertTrue(items!.isEmpty)
    }

    // MARK: - Timeline Consistency (Real-time vs Historical)

    func testTimelineConsistencyBetweenRealTimeAndHistorical() throws {
        // Build the same event sequence both ways
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .turnStarted,
                      payload: .turnStarted(turnID: "t1", input: "Hello")),
            makeEvent(seq: 2, type: .assistantDelta,
                      payload: .assistantDelta(text: "Hi!")),
            makeEvent(seq: 3, type: .turnCompleted,
                      payload: .turnCompleted(turnID: "t1")),
        ]

        // Real-time path
        let service = makeService()
        for event in events {
            try service.ingestRuntimeEvent(event)
        }
        let realTimeItems = service.timeline(runID: "test-run")

        // Historical path
        try writeTrace(events)
        let historicalItems = service.timelineFromTrace(runID: "test-run", baseDirectory: tempDir)

        // Both should produce the same timeline
        XCTAssertNotNil(historicalItems)
        XCTAssertEqual(realTimeItems.count, historicalItems!.count)

        for i in 0..<realTimeItems.count {
            XCTAssertEqual(realTimeItems[i].type, historicalItems![i].type,
                           "Type mismatch at index \(i)")
            XCTAssertEqual(realTimeItems[i].data, historicalItems![i].data,
                           "Data mismatch at index \(i)")
        }
    }

    func testTimelineConsistencyWithToolCalls() throws {
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .turnStarted,
                      payload: .turnStarted(turnID: "t1", input: "Read file")),
            makeEvent(seq: 2, type: .toolCallRequested,
                      payload: .toolCall(name: "bash", params: ["command": "cat main.swift"])),
            makeEvent(seq: 3, type: .toolCallCompleted,
                      payload: .toolCallCompleted(name: "bash", result: "fn main() {}")),
            makeEvent(seq: 4, type: .turnCompleted,
                      payload: .turnCompleted(turnID: "t1")),
        ]

        // Real-time
        let service = makeService()
        for event in events {
            try service.ingestRuntimeEvent(event)
        }
        let realTimeItems = service.timeline(runID: "test-run")

        // Historical
        try writeTrace(events)
        let historicalItems = service.timelineFromTrace(runID: "test-run", baseDirectory: tempDir)

        XCTAssertNotNil(historicalItems)
        XCTAssertEqual(realTimeItems.count, historicalItems!.count)
        XCTAssertEqual(realTimeItems.count, 4) // user + toolReq + toolComplete + result

        // Verify tool call data matches
        for i in 0..<realTimeItems.count {
            XCTAssertEqual(realTimeItems[i].data, historicalItems![i].data)
        }
    }

    func testTimelineConsistencyWithApprovals() throws {
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .approvalRequested,
                      payload: .approvalRequested(requestID: 1, tool: "rm", command: "rm -rf /tmp", riskLevel: "high")),
            makeEvent(seq: 2, type: .approvalResolved,
                      payload: .approvalResolved(requestID: 1, decision: "accept")),
        ]

        // Real-time
        let service = makeService()
        for event in events {
            try service.ingestRuntimeEvent(event)
        }
        let realTimeItems = service.timeline(runID: "test-run")

        // Historical
        try writeTrace(events)
        let historicalItems = service.timelineFromTrace(runID: "test-run", baseDirectory: tempDir)

        XCTAssertNotNil(historicalItems)
        XCTAssertEqual(realTimeItems.count, historicalItems!.count)
        XCTAssertEqual(realTimeItems.count, 2)

        XCTAssertEqual(realTimeItems[0].data, historicalItems![0].data)
        XCTAssertEqual(realTimeItems[1].data, historicalItems![1].data)
    }

    // MARK: - Empty Timeline Handling

    func testEmptyTimelineWhenNoEvents() {
        let service = makeService()
        let items = service.timeline()
        XCTAssertTrue(items.isEmpty)
    }

    func testEmptyTimelineForUnknownRunID() {
        let service = makeService()
        let items = service.timeline(runID: "nonexistent")
        XCTAssertTrue(items.isEmpty)
    }

    func testTimelineWithFallbackReturnsEmptyForUnknownRun() {
        let service = makeService()
        let items = service.timelineWithFallback(runID: "nonexistent", baseDirectory: tempDir)
        XCTAssertTrue(items.isEmpty)
    }

    func testTimelineFromTraceReturnsNilForMissingRun() {
        let service = makeService()
        let items = service.timelineFromTrace(runID: "missing", baseDirectory: tempDir)
        XCTAssertNil(items)
    }

    // MARK: - Timeline With Fallback

    func testTimelineWithFallbackPrefersInMemory() throws {
        let service = makeService()

        // Add events to in-memory
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t1", "input": "In memory"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // Also write a trace with different content
        let traceEvents: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .turnStarted,
                      payload: .turnStarted(turnID: "t1", input: "From trace"),
                      runID: "run-1"),
        ]
        try writeTrace(traceEvents, runID: "run-1")

        // Should prefer in-memory
        let items = service.timelineWithFallback(runID: "run-1", baseDirectory: tempDir)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].data, .userMessage(text: "In memory"))
    }

    func testTimelineWithFallbackFallsBackToTrace() throws {
        let service = makeService()

        // Only write to trace, nothing in memory
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .turnStarted,
                      payload: .turnStarted(turnID: "t1", input: "From trace")),
            makeEvent(seq: 2, type: .turnCompleted,
                      payload: .turnCompleted(turnID: "t1")),
        ]
        try writeTrace(events)

        let items = service.timelineWithFallback(runID: "test-run", baseDirectory: tempDir)
        XCTAssertEqual(items.count, 2) // user + finalResult (no assistant text to flush)
    }

    // MARK: - Large Timeline Performance

    func testLargeTimelinePerformance() throws {
        // Build a large event set: 500 events
        var events: [RuntimeEvent] = []
        for i in 0..<500 {
            let seq = UInt64(i + 1)
            if i % 5 == 0 {
                events.append(makeEvent(seq: seq, type: .turnStarted,
                                        payload: .turnStarted(turnID: "t\(i)", input: "Message \(i)")))
            } else if i % 5 == 1 {
                events.append(makeEvent(seq: seq, type: .assistantDelta,
                                        payload: .assistantDelta(text: "Response \(i)")))
            } else if i % 5 == 2 {
                events.append(makeEvent(seq: seq, type: .toolCallRequested,
                                        payload: .toolCall(name: "tool_\(i)", params: nil)))
            } else if i % 5 == 3 {
                events.append(makeEvent(seq: seq, type: .toolCallCompleted,
                                        payload: .toolCallCompleted(name: "tool_\(i)", result: "ok")))
            } else {
                events.append(makeEvent(seq: seq, type: .turnCompleted,
                                        payload: .turnCompleted(turnID: "t\(i - 4)")))
            }
        }

        try writeTrace(events)

        let service = makeService()

        measure {
            let items = service.timelineFromTrace(runID: "test-run", baseDirectory: tempDir)
            XCTAssertNotNil(items)
            XCTAssertGreaterThan(items!.count, 0)
        }
    }

    func testLargeInMemoryTimelinePerformance() throws {
        let service = makeService()

        // Ingest 500 events
        for i in 0..<500 {
            let event = RuntimeEvent(
                id: "evt-\(i)",
                seq: UInt64(i + 1),
                version: 1,
                timestamp: Date(timeIntervalSince1970: Double(i)),
                sessionID: "s1",
                runID: "perf-run",
                runtime: .claudeCode,
                type: .turnStarted,
                payload: .turnStarted(turnID: "t\(i)", input: "Message \(i)")
            )
            try service.ingestRuntimeEvent(event)
        }

        measure {
            let items = service.timeline(runID: "perf-run")
            XCTAssertEqual(items.count, 500)
        }
    }

    // MARK: - Run ID Filtering

    func testTimelineFiltersByRunID() throws {
        let service = makeService()

        // Events for run-1
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t1", "input": "Run 1"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // Events for run-2
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t2", "input": "Run 2"]),
            runtime: .codex, sessionID: "s1", runID: "run-2"
        )

        let run1Items = service.timeline(runID: "run-1")
        XCTAssertEqual(run1Items.count, 1)
        XCTAssertEqual(run1Items[0].data, .userMessage(text: "Run 1"))

        let run2Items = service.timeline(runID: "run-2")
        XCTAssertEqual(run2Items.count, 1)
        XCTAssertEqual(run2Items[0].data, .userMessage(text: "Run 2"))

        let allItems = service.timeline()
        XCTAssertEqual(allItems.count, 2)
    }

    // MARK: - Error Handling

    func testTurnErrorProducesErrorInTimeline() throws {
        let service = makeService()

        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t1", "input": "Hello"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        let errorEvent = RuntimeEvent(
            sessionID: "s1", runID: "run-1",
            runtime: .codex, type: .turnError,
            payload: .turnError(turnID: "t1", message: "Rate limited")
        )
        try service.ingestRuntimeEvent(errorEvent)

        let items = service.timeline(runID: "run-1")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].type, .userMessage)
        XCTAssertEqual(items[1].type, .error)
        XCTAssertEqual(items[1].data, .error(message: "Rate limited", code: nil))
    }

    func testGlobalErrorAppearsInTimeline() throws {
        let service = makeService()

        let errorEvent = RuntimeEvent(
            runtime: .codex, type: .error,
            payload: .error(message: "Connection lost", code: "ECONNRESET")
        )
        try service.ingestRuntimeEvent(errorEvent)

        let items = service.timeline()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .error)
    }

    // MARK: - File Changes

    func testFileChangesAppearInTimeline() throws {
        let service = makeService()

        let fileChange = RuntimeEvent(
            runtime: .codex, type: .fileChangeDetected,
            payload: .fileChange(path: "src/main.swift", changeKind: "modified")
        )
        try service.ingestRuntimeEvent(fileChange)

        let items = service.timeline()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .fileChange)
        XCTAssertEqual(items[0].data, .fileChange(path: "src/main.swift", changeKind: "modified"))
    }

    // MARK: - Approval Lifecycle

    func testApprovalLifecycleInTimeline() throws {
        let service = makeService()

        let requested = RuntimeEvent(
            runtime: .codex, type: .approvalRequested,
            payload: .approvalRequested(requestID: 42, tool: "bash", command: "rm -rf /tmp", riskLevel: "high")
        )
        try service.ingestRuntimeEvent(requested)

        let resolved = RuntimeEvent(
            runtime: .codex, type: .approvalResolved,
            payload: .approvalResolved(requestID: 42, decision: "accept")
        )
        try service.ingestRuntimeEvent(resolved)

        let items = service.timeline()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].data, .approval(requestID: 42, tool: "bash", command: "rm -rf /tmp", status: .pending))
        XCTAssertEqual(items[1].data, .approval(requestID: 42, tool: "", command: nil, status: .accepted))
    }

    // MARK: - Full Conversation Flow

    func testFullConversationFlow() throws {
        let service = makeService()

        // User message
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t1", "input": "Read main.swift"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // Tool call
        let toolReq = RuntimeEvent(
            sessionID: "s1", runID: "run-1",
            runtime: .codex, type: .toolCallRequested,
            payload: .toolCall(name: "read_file", params: ["path": "main.swift"])
        )
        try service.ingestRuntimeEvent(toolReq)

        let toolComplete = RuntimeEvent(
            sessionID: "s1", runID: "run-1",
            runtime: .codex, type: .toolCallCompleted,
            payload: .toolCallCompleted(name: "read_file", result: "200 lines")
        )
        try service.ingestRuntimeEvent(toolComplete)

        // Assistant response
        try service.ingestWithRuntimeEvent(
            codexNotification("item/agentMessage/delta", params: ["delta": "The file contains a main function."]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // Turn complete
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/completed", params: ["turn_id": "t1"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        let items = service.timeline(runID: "run-1")
        XCTAssertEqual(items.count, 5)

        XCTAssertEqual(items[0].type, .userMessage)
        XCTAssertEqual(items[1].type, .toolCall)
        XCTAssertEqual(items[2].type, .toolCall)
        XCTAssertEqual(items[3].type, .assistantMessage)
        XCTAssertEqual(items[4].type, .finalResult)
    }

    // MARK: - Codable Round-Trip

    func testTimelineItemsRoundTripThroughJSON() throws {
        let fixedDate = Date(timeIntervalSince1970: 1700000000)

        let items = [
            TimelineItem(id: "t1", type: .userMessage, timestamp: fixedDate,
                         data: .userMessage(text: "Hello")),
            TimelineItem(id: "t2", type: .toolCall, timestamp: fixedDate,
                         data: .toolCall(name: "bash", status: .completed, input: "ls", output: "ok")),
            TimelineItem(id: "t3", type: .error, timestamp: fixedDate,
                         data: .error(message: "Failed", code: "E1")),
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([TimelineItem].self, from: data)

        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].data, .userMessage(text: "Hello"))
        XCTAssertEqual(decoded[1].data, .toolCall(name: "bash", status: .completed, input: "ls", output: "ok"))
        XCTAssertEqual(decoded[2].data, .error(message: "Failed", code: "E1"))
    }
}
