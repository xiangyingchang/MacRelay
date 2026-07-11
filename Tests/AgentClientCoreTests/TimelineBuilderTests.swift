import XCTest
@testable import AgentClientCore

final class TimelineBuilderTests: XCTestCase {

    private let builder = TimelineBuilder()

    // MARK: - Helpers

    /// Fixed timestamp for deterministic assertions.
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_001)
    private let t2 = Date(timeIntervalSince1970: 1_700_000_002)
    private let t3 = Date(timeIntervalSince1970: 1_700_000_003)
    private let t4 = Date(timeIntervalSince1970: 1_700_000_004)
    private let t5 = Date(timeIntervalSince1970: 1_700_000_005)

    private func event(
        _ type: RuntimeEventType,
        _ payload: RuntimeEventPayload,
        at date: Date? = nil
    ) -> RuntimeEvent {
        RuntimeEvent(
            id: UUID().uuidString,
            timestamp: date ?? t0,
            runtime: .claudeCode,
            type: type,
            payload: payload
        )
    }

    // MARK: - Empty input

    func testEmptyInputReturnsEmptyTimeline() {
        let items = builder.build(from: [])
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - User message

    func testTurnStartedWithInputProducesUserMessage() {
        let events = [
            event(.turnStarted, .turnStarted(turnID: "t1", input: "Hello")),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .userMessage)
        XCTAssertEqual(items[0].data, .userMessage(text: "Hello"))
    }

    func testTurnStartedWithoutInputProducesNothing() {
        let events = [
            event(.turnStarted, .turnStarted(turnID: "t1", input: nil)),
        ]
        let items = builder.build(from: events)
        XCTAssertTrue(items.isEmpty)
    }

    func testTurnStartedWithEmptyInputProducesNothing() {
        let events = [
            event(.turnStarted, .turnStarted(turnID: "t1", input: "   ")),
        ]
        let items = builder.build(from: events)
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Assistant message (streaming → flush)

    func testDeltasAccumulateIntoAssistantMessage() {
        let events = [
            event(.turnStarted, .turnStarted(turnID: "t1", input: "Hi"), at: t0),
            event(.assistantDelta, .assistantDelta(text: "Hello "), at: t1),
            event(.assistantDelta, .assistantDelta(text: "world!"), at: t2),
            event(.turnCompleted, .turnCompleted(turnID: "t1"), at: t3),
        ]
        let items = builder.build(from: events)

        // userMessage + assistantMessage + finalResult
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].type, .userMessage)
        XCTAssertEqual(items[1].type, .assistantMessage)
        XCTAssertEqual(items[1].data, .assistantMessage(text: "Hello world!"))
        XCTAssertEqual(items[2].type, .finalResult)
    }

    func testAssistantMessageCompletedFlushesAccumulator() {
        let events = [
            event(.assistantDelta, .assistantDelta(text: "partial "), at: t0),
            event(.assistantMessageCompleted, .assistantMessageCompleted(text: "Full response."), at: t1),
            event(.turnCompleted, .turnCompleted(turnID: "t1"), at: t2),
        ]
        let items = builder.build(from: events)

        // assistantMessage (from completed) + finalResult
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].type, .assistantMessage)
        XCTAssertEqual(items[0].data, .assistantMessage(text: "Full response."))
        XCTAssertEqual(items[1].type, .finalResult)
    }

    // MARK: - Turn completed

    func testTurnCompletedEmitsFinalResult() {
        let events = [
            event(.turnCompleted, .turnCompleted(turnID: "t1"), at: t1),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .finalResult)
        XCTAssertEqual(items[0].data, .finalResult(text: "Turn completed"))
    }

    func testTurnCompletedFlushesPendingAssistantText() {
        let events = [
            event(.assistantDelta, .assistantDelta(text: "streaming..."), at: t0),
            event(.turnCompleted, .turnCompleted(turnID: "t1"), at: t1),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].type, .assistantMessage)
        XCTAssertEqual(items[0].data, .assistantMessage(text: "streaming..."))
        XCTAssertEqual(items[1].type, .finalResult)
    }

    // MARK: - Turn error

    func testTurnErrorEmitsErrorAndFlushesAssistantText() {
        let events = [
            event(.assistantDelta, .assistantDelta(text: "partial "), at: t0),
            event(.turnError, .turnError(turnID: "t1", message: "Rate limited"), at: t1),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].type, .assistantMessage)
        XCTAssertEqual(items[0].data, .assistantMessage(text: "partial "))
        XCTAssertEqual(items[1].type, .error)
        XCTAssertEqual(items[1].data, .error(message: "Rate limited", code: nil))
    }

    // MARK: - Tool calls

    func testToolCallRequestedProducesToolCallItem() {
        let events = [
            event(.toolCallRequested, .toolCall(name: "bash", params: ["command": "ls -la"]), at: t0),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .toolCall)
        if case let .toolCall(name, status, input, output) = items[0].data {
            XCTAssertEqual(name, "bash")
            XCTAssertEqual(status, .requested)
            XCTAssertNotNil(input)
            XCTAssertNil(output)
        } else {
            XCTFail("Expected toolCall data")
        }
    }

    func testToolCallCompletedProducesCompletedItem() {
        let events = [
            event(.toolCallCompleted, .toolCallCompleted(name: "bash", result: "ok"), at: t0),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .toolCall)
        if case let .toolCall(name, status, _, output) = items[0].data {
            XCTAssertEqual(name, "bash")
            XCTAssertEqual(status, .completed)
            XCTAssertEqual(output, "ok")
        } else {
            XCTFail("Expected toolCall data")
        }
    }

    func testToolCallFailedProducesFailedItem() {
        let events = [
            event(.toolCallFailed, .toolCallFailed(name: "read", error: "file not found"), at: t0),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .toolCall)
        if case let .toolCall(name, status, _, output) = items[0].data {
            XCTAssertEqual(name, "read")
            XCTAssertEqual(status, .failed)
            XCTAssertEqual(output, "file not found")
        } else {
            XCTFail("Expected toolCall data")
        }
    }

    // MARK: - Approval

    func testApprovalRequestedProducesPendingItem() {
        let events = [
            event(.approvalRequested, .approvalRequested(requestID: 42, tool: "bash", command: "rm -rf /", riskLevel: "high"), at: t0),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .approval)
        if case let .approval(requestID, tool, command, status) = items[0].data {
            XCTAssertEqual(requestID, 42)
            XCTAssertEqual(tool, "bash")
            XCTAssertEqual(command, "rm -rf /")
            XCTAssertEqual(status, .pending)
        } else {
            XCTFail("Expected approval data")
        }
    }

    func testApprovalResolvedAcceptProducesAcceptedItem() {
        let events = [
            event(.approvalResolved, .approvalResolved(requestID: 42, decision: "accept"), at: t0),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .approval)
        if case let .approval(requestID, _, _, status) = items[0].data {
            XCTAssertEqual(requestID, 42)
            XCTAssertEqual(status, .accepted)
        } else {
            XCTFail("Expected approval data")
        }
    }

    func testApprovalResolvedRejectProducesRejectedItem() {
        let events = [
            event(.approvalResolved, .approvalResolved(requestID: 42, decision: "reject"), at: t0),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 1)
        if case let .approval(_, _, _, status) = items[0].data {
            XCTAssertEqual(status, .rejected)
        } else {
            XCTFail("Expected approval data")
        }
    }

    // MARK: - File change

    func testFileChangeProducesFileChangeItem() {
        let events = [
            event(.fileChangeDetected, .fileChange(path: "src/main.swift", changeKind: "modified"), at: t0),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .fileChange)
        XCTAssertEqual(items[0].data, .fileChange(path: "src/main.swift", changeKind: "modified"))
    }

    // MARK: - Global error

    func testGlobalErrorProducesErrorItem() {
        let events = [
            event(.error, .error(message: "Connection lost", code: "ECONNRESET"), at: t0),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].type, .error)
        XCTAssertEqual(items[0].data, .error(message: "Connection lost", code: "ECONNRESET"))
    }

    // MARK: - Ignored events

    func testIgnoredEventsProduceNothing() {
        let events = [
            event(.sessionStarted, .sessionStarted(sessionID: "s1", cwd: "/tmp"), at: t0),
            event(.settingsUpdated, .settingsUpdated(model: "gpt-4", effort: "high"), at: t1),
            event(.diffUpdated, .diffUpdated(files: ["a.swift"]), at: t2),
            event(.exited, .exited(code: 0), at: t3),
        ]
        let items = builder.build(from: events)
        XCTAssertTrue(items.isEmpty)
    }

    // MARK: - Full conversation flow

    func testFullConversationProducesCorrectTimeline() {
        let events: [RuntimeEvent] = [
            // 1. User sends a message
            event(.turnStarted, .turnStarted(turnID: "t1", input: "Read main.swift"), at: t0),
            // 2. Tool call starts
            event(.toolCallRequested, .toolCall(name: "read_file", params: ["path": "main.swift"]), at: t1),
            // 3. Tool call finishes
            event(.toolCallCompleted, .toolCallCompleted(name: "read_file", result: "200 lines"), at: t2),
            // 4. Assistant streams a response
            event(.assistantDelta, .assistantDelta(text: "The file contains "), at: t3),
            event(.assistantDelta, .assistantDelta(text: "a main function."), at: t4),
            // 5. Turn completes
            event(.turnCompleted, .turnCompleted(turnID: "t1"), at: t5),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 5)

        // User message
        XCTAssertEqual(items[0].type, .userMessage)
        XCTAssertEqual(items[0].data, .userMessage(text: "Read main.swift"))
        XCTAssertEqual(items[0].timestamp, t0)

        // Tool call requested
        XCTAssertEqual(items[1].type, .toolCall)
        if case let .toolCall(name, status, _, _) = items[1].data {
            XCTAssertEqual(name, "read_file")
            XCTAssertEqual(status, .requested)
        }

        // Tool call completed
        XCTAssertEqual(items[2].type, .toolCall)
        if case let .toolCall(name, status, _, output) = items[2].data {
            XCTAssertEqual(name, "read_file")
            XCTAssertEqual(status, .completed)
            XCTAssertEqual(output, "200 lines")
        }

        // Assistant message (accumulated deltas)
        XCTAssertEqual(items[3].type, .assistantMessage)
        XCTAssertEqual(items[3].data, .assistantMessage(text: "The file contains a main function."))

        // Final result
        XCTAssertEqual(items[4].type, .finalResult)
    }

    // MARK: - Multiple turns

    func testMultipleTurnsProduceDistinctItems() {
        let events: [RuntimeEvent] = [
            // Turn 1
            event(.turnStarted, .turnStarted(turnID: "t1", input: "Hello"), at: t0),
            event(.assistantDelta, .assistantDelta(text: "Hi!"), at: t1),
            event(.turnCompleted, .turnCompleted(turnID: "t1"), at: t2),
            // Turn 2
            event(.turnStarted, .turnStarted(turnID: "t2", input: "Bye"), at: t3),
            event(.assistantDelta, .assistantDelta(text: "Goodbye!"), at: t4),
            event(.turnCompleted, .turnCompleted(turnID: "t2"), at: t5),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 6)
        // Turn 1: user + assistant + result
        XCTAssertEqual(items[0].type, .userMessage)
        XCTAssertEqual(items[1].type, .assistantMessage)
        XCTAssertEqual(items[2].type, .finalResult)
        // Turn 2: user + assistant + result
        XCTAssertEqual(items[3].type, .userMessage)
        XCTAssertEqual(items[4].type, .assistantMessage)
        XCTAssertEqual(items[5].type, .finalResult)
    }

    // MARK: - Approval + error combo

    func testApprovalThenErrorProducesCorrectSequence() {
        let events: [RuntimeEvent] = [
            event(.turnStarted, .turnStarted(turnID: "t1", input: "Delete file"), at: t0),
            event(.approvalRequested, .approvalRequested(requestID: 10, tool: "bash", command: "rm tmp.txt", riskLevel: "high"), at: t1),
            event(.approvalResolved, .approvalResolved(requestID: 10, decision: "reject"), at: t2),
            event(.turnError, .turnError(turnID: "t1", message: "User rejected"), at: t3),
        ]
        let items = builder.build(from: events)

        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items[0].type, .userMessage)
        XCTAssertEqual(items[1].type, .approval)
        if case let .approval(_, _, _, status) = items[1].data {
            XCTAssertEqual(status, .pending)
        }
        XCTAssertEqual(items[2].type, .approval)
        if case let .approval(_, _, _, status) = items[2].data {
            XCTAssertEqual(status, .rejected)
        }
        XCTAssertEqual(items[3].type, .error)
    }

    // MARK: - Codable round-trip

    func testTimelineItemRoundTripsThroughJSON() throws {
        let original = TimelineItem(
            id: "test-1",
            type: .toolCall,
            timestamp: t0,
            data: .toolCall(name: "bash", status: .completed, input: "ls", output: "ok")
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TimelineItem.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testTimelineItemArrayRoundTripsThroughJSON() throws {
        let events: [RuntimeEvent] = [
            event(.turnStarted, .turnStarted(turnID: "t1", input: "Hi"), at: t0),
            event(.assistantDelta, .assistantDelta(text: "Hello!"), at: t1),
            event(.turnCompleted, .turnCompleted(turnID: "t1"), at: t2),
        ]
        let items = builder.build(from: events)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(items)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([TimelineItem].self, from: data)

        XCTAssertEqual(items, decoded)
    }
}
