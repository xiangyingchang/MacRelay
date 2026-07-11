import XCTest
@testable import AgentClientCore

final class TraceWriterTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TraceWriterTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeEvent(seq: UInt64, type: RuntimeEventType = .sessionStarted) -> RuntimeEvent {
        RuntimeEvent(
            id: "evt-\(seq)",
            seq: seq,
            version: 1,
            timestamp: Date(timeIntervalSince1970: Double(seq) * 1000),
            sessionID: "test-session",
            runID: "test-run",
            runtime: .claudeCode,
            type: type,
            payload: .sessionStarted(sessionID: "thread-\(seq)", cwd: "/tmp")
        )
    }

    private func readLines(from url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        let lines = String(data: data, encoding: .utf8)!.split(separator: "\n").map(String.init)
        return try lines.map { line in
            let obj = try JSONSerialization.jsonObject(with: Data(line.utf8))
            return obj as! [String: Any]
        }
    }

    // MARK: - Tests

    /// Test appending a single event via TraceStore protocol.
    func testAppendSingleEvent() throws {
        let writer = TraceWriter(runID: "test-run", baseDirectory: tempDir)

        let event = makeEvent(seq: 1)
        try writer.append(event)

        XCTAssertEqual(writer.count, 1)
    }

    /// Test appending multiple events via TraceStore protocol.
    func testAppendMultipleEvents() throws {
        let writer = TraceWriter(runID: "test-run", baseDirectory: tempDir)

        let events = (1...10).map { makeEvent(seq: UInt64($0)) }
        try writer.append(contentsOf: events)

        XCTAssertEqual(writer.count, 10)
    }

    /// Test order preservation.
    func testOrderPreservation() throws {
        let writer = TraceWriter(runID: "test-run", baseDirectory: tempDir)

        let events = (1...5).map { makeEvent(seq: UInt64($0)) }
        try writer.append(contentsOf: events)

        let readEvents = try writer.readAll()

        XCTAssertEqual(readEvents.count, 5)
        for (index, event) in readEvents.enumerated() {
            XCTAssertEqual(event.seq, UInt64(index + 1))
        }
    }

    /// Test reading events after a specific sequence number.
    func testReadAfterSeq() throws {
        let writer = TraceWriter(runID: "test-run", baseDirectory: tempDir)

        let events = (1...10).map { makeEvent(seq: UInt64($0)) }
        try writer.append(contentsOf: events)

        let afterEvents = try writer.read(afterSeq: 5)

        XCTAssertEqual(afterEvents.count, 5)
        XCTAssertEqual(afterEvents.first?.seq, 6)
        XCTAssertEqual(afterEvents.last?.seq, 10)
    }

    /// Test crash recovery - events persist after writer is deallocated.
    func testCrashRecovery() throws {
        // Write events with first writer
        do {
            let writer = TraceWriter(runID: "test-run", baseDirectory: tempDir)
            let events = (1...5).map { makeEvent(seq: UInt64($0)) }
            try writer.append(contentsOf: events)
        }

        // Create new writer (simulates app restart)
        let writer2 = TraceWriter(runID: "test-run", baseDirectory: tempDir)

        // Read events from new writer
        let readEvents = try writer2.readAll()

        XCTAssertEqual(readEvents.count, 5)
        XCTAssertEqual(writer2.count, 5)
    }

    /// Test encode/decode round-trip with various payload types.
    func testEncodeDecodeRoundTrip() throws {
        let writer = TraceWriter(runID: "test-run", baseDirectory: tempDir)

        // Create events with various payload types
        let events: [RuntimeEvent] = [
            RuntimeEvent(
                id: "evt-1", seq: 1, version: 1,
                timestamp: Date(timeIntervalSince1970: 1000),
                sessionID: "session-1", runID: "run-1",
                runtime: .claudeCode, type: .sessionStarted,
                payload: .sessionStarted(sessionID: "session-1", cwd: "/tmp")
            ),
            RuntimeEvent(
                id: "evt-2", seq: 2, version: 1,
                timestamp: Date(timeIntervalSince1970: 2000),
                sessionID: "session-1", runID: "run-1",
                runtime: .claudeCode, type: .turnStarted,
                payload: .turnStarted(turnID: "turn-1", input: "Fix the bug")
            ),
            RuntimeEvent(
                id: "evt-3", seq: 3, version: 1,
                timestamp: Date(timeIntervalSince1970: 3000),
                sessionID: "session-1", runID: "run-1",
                runtime: .claudeCode, type: .approvalRequested,
                payload: .approvalRequested(requestID: 1, tool: "write_file", command: "write LoginView.swift", riskLevel: "medium")
            ),
            RuntimeEvent(
                id: "evt-4", seq: 4, version: 1,
                timestamp: Date(timeIntervalSince1970: 4000),
                sessionID: "session-1", runID: "run-1",
                runtime: .claudeCode, type: .fileChangeDetected,
                payload: .fileChange(path: "Sources/App/LoginView.swift", changeKind: "modified")
            ),
            RuntimeEvent(
                id: "evt-5", seq: 5, version: 1,
                timestamp: Date(timeIntervalSince1970: 5000),
                sessionID: "session-1", runID: "run-1",
                runtime: .claudeCode, type: .turnCompleted,
                payload: .turnCompleted(turnID: "turn-1")
            )
        ]

        try writer.append(contentsOf: events)

        // Read back and verify
        let readEvents = try writer.readAll()

        XCTAssertEqual(readEvents.count, 5)

        // Verify each event
        XCTAssertEqual(readEvents[0].type, .sessionStarted)
        if case let .sessionStarted(sessionID, cwd) = readEvents[0].payload {
            XCTAssertEqual(sessionID, "session-1")
            XCTAssertEqual(cwd, "/tmp")
        } else {
            XCTFail("Expected sessionStarted payload")
        }

        XCTAssertEqual(readEvents[1].type, .turnStarted)
        if case let .turnStarted(turnID, input) = readEvents[1].payload {
            XCTAssertEqual(turnID, "turn-1")
            XCTAssertEqual(input, "Fix the bug")
        } else {
            XCTFail("Expected turnStarted payload")
        }

        XCTAssertEqual(readEvents[2].type, .approvalRequested)
        if case let .approvalRequested(requestID, tool, command, riskLevel) = readEvents[2].payload {
            XCTAssertEqual(requestID, 1)
            XCTAssertEqual(tool, "write_file")
            XCTAssertEqual(command, "write LoginView.swift")
            XCTAssertEqual(riskLevel, "medium")
        } else {
            XCTFail("Expected approvalRequested payload")
        }

        XCTAssertEqual(readEvents[3].type, .fileChangeDetected)
        if case let .fileChange(path, changeKind) = readEvents[3].payload {
            XCTAssertEqual(path, "Sources/App/LoginView.swift")
            XCTAssertEqual(changeKind, "modified")
        } else {
            XCTFail("Expected fileChange payload")
        }

        XCTAssertEqual(readEvents[4].type, .turnCompleted)
        if case let .turnCompleted(turnID) = readEvents[4].payload {
            XCTAssertEqual(turnID, "turn-1")
        } else {
            XCTFail("Expected turnCompleted payload")
        }
    }

    /// Test InMemoryTraceStore.
    func testInMemoryTraceStore() throws {
        let store = InMemoryTraceStore(runID: "test-run", sessionID: "test-session")

        let events = (1...5).map { makeEvent(seq: UInt64($0)) }
        try store.append(contentsOf: events)

        XCTAssertEqual(store.count, 5)
        XCTAssertEqual(store.runID, "test-run")
        XCTAssertEqual(store.sessionID, "test-session")

        let all = try store.readAll()
        XCTAssertEqual(all.count, 5)

        let after3 = try store.read(afterSeq: 3)
        XCTAssertEqual(after3.count, 2)
        XCTAssertEqual(after3.first?.seq, 4)
    }

    /// Test writing a complete Agent Run.
    func testCompleteAgentRun() throws {
        let writer = TraceWriter(runID: "run-001", sessionID: "session-001", baseDirectory: tempDir)

        // Simulate a complete Agent Run
        let events: [RuntimeEvent] = [
            // Session starts
            RuntimeEvent(seq: 1, runtime: .claudeCode, type: .sessionStarted,
                        payload: .sessionStarted(sessionID: "session-001", cwd: "/tmp/project")),
            // Turn starts
            RuntimeEvent(seq: 2, runtime: .claudeCode, type: .turnStarted,
                        payload: .turnStarted(turnID: "turn-001", input: "Fix login bug")),
            // Assistant response
            RuntimeEvent(seq: 3, runtime: .claudeCode, type: .assistantDelta,
                        payload: .assistantDelta(text: "I'll fix the login bug")),
            // Tool call
            RuntimeEvent(seq: 4, runtime: .claudeCode, type: .toolCallRequested,
                        payload: .toolCall(name: "read_file", params: ["path": "LoginView.swift"])),
            // Approval
            RuntimeEvent(seq: 5, runtime: .claudeCode, type: .approvalRequested,
                        payload: .approvalRequested(requestID: 1, tool: "write_file", command: nil, riskLevel: "medium")),
            RuntimeEvent(seq: 6, runtime: .claudeCode, type: .approvalResolved,
                        payload: .approvalResolved(requestID: 1, decision: "allow")),
            // File change
            RuntimeEvent(seq: 7, runtime: .claudeCode, type: .fileChangeDetected,
                        payload: .fileChange(path: "LoginView.swift", changeKind: "modified")),
            // Turn completes
            RuntimeEvent(seq: 8, runtime: .claudeCode, type: .turnCompleted,
                        payload: .turnCompleted(turnID: "turn-001"))
        ]

        try writer.append(contentsOf: events)

        // Verify the trace file exists
        let traceURL = tempDir.appendingPathComponent("run-001/trace.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: traceURL.path))

        // Read back and verify
        let readEvents = try writer.readAll()
        XCTAssertEqual(readEvents.count, 8)

        // Verify sequence
        for (index, event) in readEvents.enumerated() {
            XCTAssertEqual(event.seq, UInt64(index + 1))
        }

        // Verify first and last events
        XCTAssertEqual(readEvents.first?.type, .sessionStarted)
        XCTAssertEqual(readEvents.last?.type, .turnCompleted)
    }

    /// Test JSON contains required fields.
    func testJSONContainsRequiredFields() throws {
        let writer = TraceWriter(runID: "test-run", baseDirectory: tempDir)

        let event = makeEvent(seq: 42, type: .turnStarted)
        try writer.append(event)

        // Read the raw JSON line
        let traceURL = tempDir.appendingPathComponent("test-run/trace.jsonl")
        let data = try Data(contentsOf: traceURL)
        let lines = String(data: data, encoding: .utf8)!.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 1)

        let line = lines[0]
        let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]

        XCTAssertNotNil(obj["id"])
        XCTAssertEqual(obj["seq"] as? UInt64, 42)
        XCTAssertEqual(obj["version"] as? Int, 1)
        XCTAssertNotNil(obj["timestamp"])
        XCTAssertEqual(obj["sessionID"] as? String, "test-session")
        XCTAssertEqual(obj["runID"] as? String, "test-run")
        XCTAssertEqual(obj["runtime"] as? String, RuntimeIdentifier.claudeCode.rawValue)
        XCTAssertEqual(obj["type"] as? String, RuntimeEventType.turnStarted.rawValue)
        XCTAssertNotNil(obj["payload"])
    }

    /// Test creates parent directories.
    func testCreatesParentDirectories() throws {
        let writer = TraceWriter(runID: "run-001", baseDirectory: tempDir)

        let event = makeEvent(seq: 1)
        try writer.append(event)

        let traceURL = tempDir.appendingPathComponent("run-001/trace.jsonl")
        XCTAssertTrue(FileManager.default.fileExists(atPath: traceURL.path))
    }
}
