import XCTest
@testable import AgentClientCore

/// Integration tests for the Timeline feature.
///
/// Tests the full pipeline: RuntimeEvent → MacRelayService → TimelineBuilder → [TimelineItem]
final class TimelineIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> MacRelayService {
        MacRelayService()
    }

    /// Create a CodexAppServerEvent that will produce RuntimeEvents via the adapter.
    private func codexNotification(_ method: String, params: [String: Any]) -> CodexAppServerEvent {
        .notification(method: method, params: params)
    }

    // MARK: - Empty Timeline

    func testTimelineIsEmptyWhenNoEvents() {
        let service = makeService()
        let items = service.timeline()
        XCTAssertTrue(items.isEmpty)
    }

    func testTimelineIsEmptyForUnknownRunID() {
        let service = makeService()
        let items = service.timeline(runID: "nonexistent-run")
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Single Event Pipeline

    func testTurnStartedProducesUserMessage() throws {
        let service = makeService()

        let event = codexNotification("turn/started", params: [
            "turn_id": "turn-1",
            "input": "Fix the bug"
        ])
        let (_, runtimeEvents) = try service.ingestWithRuntimeEvent(
            event, runtime: .codex, sessionID: "session-1", runID: "run-1"
        )

        XCTAssertEqual(runtimeEvents.count, 1)
        XCTAssertEqual(runtimeEvents[0].type, .turnStarted)

        let items = service.timeline(runID: "run-1")
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .userMessage)
    }

    func testAssistantDeltaProducesAssistantMessage() throws {
        let service = makeService()

        // Start a turn first
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "turn-1", "input": "Hi"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // Stream deltas
        try service.ingestWithRuntimeEvent(
            codexNotification("item/agentMessage/delta", params: ["delta": "Hello "]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )
        try service.ingestWithRuntimeEvent(
            codexNotification("item/agentMessage/delta", params: ["delta": "world!"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // Complete the turn
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/completed", params: ["turn_id": "turn-1"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        let items = service.timeline(runID: "run-1")
        XCTAssertEqual(items.count, 3) // user + assistant + finalResult

        XCTAssertEqual(items[0].type, .userMessage)
        XCTAssertEqual(items[1].type, .assistantMessage)
        XCTAssertEqual(items[1].data, .assistantMessage(text: "Hello world!"))
        XCTAssertEqual(items[2].type, .finalResult)
    }

    // MARK: - Tool Call Pipeline

    func testToolCallLifecycle() throws {
        let service = makeService()

        // Tool call requested
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t1", "input": "Read file"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // Note: tool.call.requested/completed/failed are RuntimeEvent types
        // that don't map directly from Codex notifications.
        // We ingest them directly as RuntimeEvents with runID.
        let toolRequested = RuntimeEvent(
            sessionID: "s1", runID: "run-1",
            runtime: .codex, type: .toolCallRequested,
            payload: .toolCall(name: "read_file", params: ["path": "main.swift"])
        )
        try service.ingestRuntimeEvent(toolRequested)

        let toolCompleted = RuntimeEvent(
            sessionID: "s1", runID: "run-1",
            runtime: .codex, type: .toolCallCompleted,
            payload: .toolCallCompleted(name: "read_file", result: "200 lines")
        )
        try service.ingestRuntimeEvent(toolCompleted)

        try service.ingestWithRuntimeEvent(
            codexNotification("turn/completed", params: ["turn_id": "t1"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        let items = service.timeline(runID: "run-1")

        // Should have: userMessage, toolCall(requested), toolCall(completed), finalResult
        XCTAssertEqual(items.count, 4)

        // Verify tool call items
        let toolItems = items.filter { $0.type == .toolCall }
        XCTAssertEqual(toolItems.count, 2)
    }

    // MARK: - Approval Pipeline

    func testApprovalLifecycle() throws {
        let service = makeService()

        // Approval requested
        let approvalRequested = RuntimeEvent(
            runtime: .codex, type: .approvalRequested,
            payload: .approvalRequested(requestID: 42, tool: "bash", command: "rm -rf /tmp", riskLevel: "high")
        )
        try service.ingestRuntimeEvent(approvalRequested)

        // Approval resolved
        let approvalResolved = RuntimeEvent(
            runtime: .codex, type: .approvalResolved,
            payload: .approvalResolved(requestID: 42, decision: "accept")
        )
        try service.ingestRuntimeEvent(approvalResolved)

        let items = service.timeline()
        XCTAssertEqual(items.count, 2)

        XCTAssertEqual(items[0].type, .approval)
        XCTAssertEqual(items[0].data, .approval(requestID: 42, tool: "bash", command: "rm -rf /tmp", status: .pending))

        XCTAssertEqual(items[1].type, .approval)
        XCTAssertEqual(items[1].data, .approval(requestID: 42, tool: "", command: nil, status: .accepted))
    }

    // MARK: - Error Pipeline

    func testErrorProducesErrorItem() throws {
        let service = makeService()

        let errorEvent = RuntimeEvent(
            runtime: .codex, type: .error,
            payload: .error(message: "Connection lost", code: "ECONNRESET")
        )
        try service.ingestRuntimeEvent(errorEvent)

        let items = service.timeline()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .error)
        XCTAssertEqual(items[0].data, .error(message: "Connection lost", code: "ECONNRESET"))
    }

    func testTurnErrorProducesError() throws {
        let service = makeService()

        // Start turn
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t1", "input": "Hello"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // Turn error - use same runID so it appears in filtered timeline
        let turnError = RuntimeEvent(
            sessionID: "s1", runID: "run-1",
            runtime: .codex, type: .turnError,
            payload: .turnError(turnID: "t1", message: "Rate limited")
        )
        try service.ingestRuntimeEvent(turnError)

        let items = service.timeline(runID: "run-1")
        // turnError produces: userMessage + error (no finalResult for errors)
        XCTAssertEqual(items.count, 2)

        XCTAssertEqual(items[0].type, .userMessage)
        XCTAssertEqual(items[1].type, .error)
        XCTAssertEqual(items[1].data, .error(message: "Rate limited", code: nil))
    }

    // MARK: - File Change Pipeline

    func testFileChangeProducesFileChangeItem() throws {
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

    // MARK: - Run ID Filtering

    func testTimelineFiltersByRunID() throws {
        let service = makeService()

        // Events for run-1
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t1", "input": "Run 1 message"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // Events for run-2
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t2", "input": "Run 2 message"]),
            runtime: .codex, sessionID: "s1", runID: "run-2"
        )

        // All events
        let allItems = service.timeline()
        XCTAssertEqual(allItems.count, 2)

        // Only run-1
        let run1Items = service.timeline(runID: "run-1")
        XCTAssertEqual(run1Items.count, 1)
        XCTAssertEqual(run1Items[0].data, .userMessage(text: "Run 1 message"))

        // Only run-2
        let run2Items = service.timeline(runID: "run-2")
        XCTAssertEqual(run2Items.count, 1)
        XCTAssertEqual(run2Items[0].data, .userMessage(text: "Run 2 message"))
    }

    // MARK: - Full Conversation Flow

    func testFullConversationProducesCorrectTimeline() throws {
        let service = makeService()

        // 1. User sends message
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t1", "input": "Read main.swift"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // 2. Assistant streams response
        try service.ingestWithRuntimeEvent(
            codexNotification("item/agentMessage/delta", params: ["delta": "The file "]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )
        try service.ingestWithRuntimeEvent(
            codexNotification("item/agentMessage/delta", params: ["delta": "contains a main function."]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // 3. Turn completes
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/completed", params: ["turn_id": "t1"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        let items = service.timeline(runID: "run-1")
        XCTAssertEqual(items.count, 3)

        XCTAssertEqual(items[0].type, .userMessage)
        XCTAssertEqual(items[0].data, .userMessage(text: "Read main.swift"))

        XCTAssertEqual(items[1].type, .assistantMessage)
        XCTAssertEqual(items[1].data, .assistantMessage(text: "The file contains a main function."))

        XCTAssertEqual(items[2].type, .finalResult)
    }

    // MARK: - Timeline Updates on New Events

    func testTimelineUpdatesWhenNewEventsArrive() throws {
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

        // Add more events
        try service.ingestWithRuntimeEvent(
            codexNotification("item/agentMessage/delta", params: ["delta": "Hi!"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/completed", params: ["turn_id": "t1"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        items = service.timeline(runID: "run-1")
        XCTAssertEqual(items.count, 3) // user + assistant + finalResult
    }

    // MARK: - Multiple Turns

    func testMultipleTurnsProduceDistinctItems() throws {
        let service = makeService()

        // Turn 1
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t1", "input": "Hello"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )
        try service.ingestWithRuntimeEvent(
            codexNotification("item/agentMessage/delta", params: ["delta": "Hi!"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/completed", params: ["turn_id": "t1"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        // Turn 2
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/started", params: ["turn_id": "t2", "input": "Bye"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )
        try service.ingestWithRuntimeEvent(
            codexNotification("item/agentMessage/delta", params: ["delta": "Goodbye!"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )
        try service.ingestWithRuntimeEvent(
            codexNotification("turn/completed", params: ["turn_id": "t2"]),
            runtime: .codex, sessionID: "s1", runID: "run-1"
        )

        let items = service.timeline(runID: "run-1")
        XCTAssertEqual(items.count, 6)

        // Turn 1: user + assistant + result
        XCTAssertEqual(items[0].type, .userMessage)
        XCTAssertEqual(items[0].data, .userMessage(text: "Hello"))
        XCTAssertEqual(items[1].type, .assistantMessage)
        XCTAssertEqual(items[1].data, .assistantMessage(text: "Hi!"))
        XCTAssertEqual(items[2].type, .finalResult)

        // Turn 2: user + assistant + result
        XCTAssertEqual(items[3].type, .userMessage)
        XCTAssertEqual(items[3].data, .userMessage(text: "Bye"))
        XCTAssertEqual(items[4].type, .assistantMessage)
        XCTAssertEqual(items[4].data, .assistantMessage(text: "Goodbye!"))
        XCTAssertEqual(items[5].type, .finalResult)
    }

    // MARK: - Codable Round-Trip

    func testTimelineItemsRoundTripThroughJSON() throws {
        // Create a fixed timestamp for deterministic comparison
        let fixedDate = Date(timeIntervalSince1970: 1700000000)

        let item = TimelineItem(
            id: "test-1",
            type: .userMessage,
            timestamp: fixedDate,
            data: .userMessage(text: "Test message")
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([item])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([TimelineItem].self, from: data)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, "test-1")
        XCTAssertEqual(decoded[0].type, .userMessage)
        XCTAssertEqual(decoded[0].data, .userMessage(text: "Test message"))
        // Compare timestamps with tolerance for ISO8601 precision
        XCTAssertEqual(decoded[0].timestamp.timeIntervalSince1970,
                       fixedDate.timeIntervalSince1970,
                       accuracy: 0.001)
    }
}
