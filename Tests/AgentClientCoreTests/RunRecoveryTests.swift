import XCTest
@testable import AgentClientCore

final class RunRecoveryTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunRecoveryTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func writeTrace(_ events: [RuntimeEvent], runID: String = "test-run") throws {
        let writer = TraceWriter(runID: runID, baseDirectory: tempDir)
        try writer.append(contentsOf: events)
    }

    private func writeRawLines(_ lines: [String], runID: String = "test-run") throws {
        let dir = tempDir.appendingPathComponent(runID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("trace.jsonl")
        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: file, atomically: true, encoding: .utf8)
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

    // MARK: - Normal Completed Run Recovery

    func testNormalCompletedRunRecovery() throws {
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .sessionStarted,
                      payload: .sessionStarted(sessionID: "session-1", cwd: "/tmp")),
            makeEvent(seq: 2, type: .runStarted,
                      payload: .runStarted(runID: "test-run", input: "Fix the bug")),
            makeEvent(seq: 3, type: .turnStarted,
                      payload: .turnStarted(turnID: "turn-1", input: "Fix the bug")),
            makeEvent(seq: 4, type: .assistantDelta,
                      payload: .assistantDelta(text: "I'll fix it")),
            makeEvent(seq: 5, type: .toolCallRequested,
                      payload: .toolCall(name: "read_file", params: ["path": "bug.swift"])),
            makeEvent(seq: 6, type: .toolCallCompleted,
                      payload: .toolCallCompleted(name: "read_file", result: "contents")),
            makeEvent(seq: 7, type: .assistantDelta,
                      payload: .assistantDelta(text: " Found the issue")),
            makeEvent(seq: 8, type: .turnCompleted,
                      payload: .turnCompleted(turnID: "turn-1")),
            makeEvent(seq: 9, type: .runCompleted,
                      payload: .runCompleted(runID: "test-run", summary: "Bug fixed"))
        ]

        try writeTrace(events)

        let service = RunRecoveryService(baseDirectory: tempDir)
        let recovered = try service.recover(runID: "test-run")

        // Run metadata
        XCTAssertEqual(recovered.run.id, "test-run")
        XCTAssertEqual(recovered.run.status, .completed)
        XCTAssertEqual(recovered.run.input, "Fix the bug")
        XCTAssertEqual(recovered.run.resultSummary, "Bug fixed")
        XCTAssertEqual(recovered.run.sessionID, "session-1")
        XCTAssertEqual(recovered.run.runtime, .claudeCode)

        // Events are preserved
        XCTAssertEqual(recovered.events.count, 9)

        // Snapshot was rebuilt
        XCTAssertEqual(recovered.snapshot.status, .completed)

        // Timeline was built
        XCTAssertFalse(recovered.timeline.isEmpty)

        // No warnings
        XCTAssertTrue(recovered.warnings.isEmpty)
    }

    // MARK: - Run Waiting for Approval

    func testRunWaitingForApproval() throws {
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .runStarted,
                      payload: .runStarted(runID: "test-run", input: "Delete file")),
            makeEvent(seq: 2, type: .turnStarted,
                      payload: .turnStarted(turnID: "turn-1", input: "Delete file")),
            makeEvent(seq: 3, type: .approvalRequested,
                      payload: .approvalRequested(requestID: 1, tool: "rm", command: "rm -rf /tmp", riskLevel: "high")),
        ]

        try writeTrace(events)

        let service = RunRecoveryService(baseDirectory: tempDir)
        let recovered = try service.recover(runID: "test-run")

        // Run is not terminal — trace was cut while waiting for approval
        XCTAssertEqual(recovered.run.status, .running)

        // Should warn about incomplete run
        XCTAssertTrue(recovered.warnings.contains(.incompleteRun("Run ended in non-terminal state: running")))
    }

    // MARK: - Run with Tool Failures

    func testRunWithToolFailures() throws {
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .runStarted,
                      payload: .runStarted(runID: "test-run", input: "Build project")),
            makeEvent(seq: 2, type: .turnStarted,
                      payload: .turnStarted(turnID: "turn-1", input: "Build project")),
            makeEvent(seq: 3, type: .toolCallRequested,
                      payload: .toolCall(name: "bash", params: ["command": "swift build"])),
            makeEvent(seq: 4, type: .toolCallFailed,
                      payload: .toolCallFailed(name: "bash", error: "Build failed: missing module")),
            makeEvent(seq: 5, type: .assistantDelta,
                      payload: .assistantDelta(text: "The build failed")),
            makeEvent(seq: 6, type: .runFailed,
                      payload: .runFailed(runID: "test-run", error: "Build failed"))
        ]

        try writeTrace(events)

        let service = RunRecoveryService(baseDirectory: tempDir)
        let recovered = try service.recover(runID: "test-run")

        XCTAssertEqual(recovered.run.status, .failed)
        XCTAssertEqual(recovered.run.resultSummary, "Build failed")

        // Timeline should contain the tool failure
        let toolItems = recovered.timeline.filter { $0.type == .toolCall }
        XCTAssertFalse(toolItems.isEmpty)
    }

    // MARK: - Incomplete Trace (App Crash Mid-Run)

    func testIncompleteTraceAppCrash() throws {
        // Simulate crash: run started but no terminal event
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .runStarted,
                      payload: .runStarted(runID: "test-run", input: "Long task")),
            makeEvent(seq: 2, type: .turnStarted,
                      payload: .turnStarted(turnID: "turn-1", input: "Long task")),
            makeEvent(seq: 3, type: .assistantDelta,
                      payload: .assistantDelta(text: "Working on it...")),
            makeEvent(seq: 4, type: .toolCallRequested,
                      payload: .toolCall(name: "bash", params: ["command": "sleep 100"]))
            // Crash here — no turnCompleted, no runCompleted
        ]

        try writeTrace(events)

        let service = RunRecoveryService(baseDirectory: tempDir)
        let recovered = try service.recover(runID: "test-run")

        // Should still recover what we have
        XCTAssertEqual(recovered.run.status, .running)
        XCTAssertEqual(recovered.events.count, 4)

        // Should warn about incomplete run
        let incompleteWarnings = recovered.warnings.filter {
            if case .incompleteRun = $0 { return true }
            return false
        }
        XCTAssertFalse(incompleteWarnings.isEmpty)
    }

    // MARK: - Empty Trace

    func testEmptyTrace() throws {
        // Write an empty file
        let dir = tempDir.appendingPathComponent("empty-run")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("trace.jsonl")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let service = RunRecoveryService(baseDirectory: tempDir)
        let recovered = try service.recover(runID: "empty-run")

        XCTAssertEqual(recovered.events.count, 0)
        XCTAssertEqual(recovered.run.status, .failed)
        XCTAssertTrue(recovered.timeline.isEmpty)

        let incompleteWarnings = recovered.warnings.filter {
            if case .incompleteRun = $0 { return true }
            return false
        }
        XCTAssertFalse(incompleteWarnings.isEmpty)
    }

    // MARK: - Duplicate Seq Detection

    func testDuplicateSeqDetection() throws {
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .runStarted,
                      payload: .runStarted(runID: "test-run", input: "Test")),
            makeEvent(seq: 2, type: .turnStarted,
                      payload: .turnStarted(turnID: "turn-1", input: "Test")),
            // Duplicate seq 2
            makeEvent(seq: 2, type: .assistantDelta,
                      payload: .assistantDelta(text: "Duplicate")),
            makeEvent(seq: 3, type: .runCompleted,
                      payload: .runCompleted(runID: "test-run", summary: nil))
        ]

        try writeTrace(events)

        let service = RunRecoveryService(baseDirectory: tempDir)
        let recovered = try service.recover(runID: "test-run")

        // Duplicate should be detected and skipped
        XCTAssertEqual(recovered.events.count, 3) // seq 1, 2 (first), 3

        let duplicateWarnings = recovered.warnings.filter {
            if case .duplicateSeq = $0 { return true }
            return false
        }
        XCTAssertEqual(duplicateWarnings.count, 1)
    }

    // MARK: - Missing Seq Detection

    func testMissingSeqDetection() throws {
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .runStarted,
                      payload: .runStarted(runID: "test-run", input: "Test")),
            // Skip seq 2
            makeEvent(seq: 3, type: .turnStarted,
                      payload: .turnStarted(turnID: "turn-1", input: "Test")),
            // Skip seq 4
            makeEvent(seq: 5, type: .runCompleted,
                      payload: .runCompleted(runID: "test-run", summary: nil))
        ]

        try writeTrace(events)

        let service = RunRecoveryService(baseDirectory: tempDir)
        let recovered = try service.recover(runID: "test-run")

        let missingWarnings = recovered.warnings.filter {
            if case .missingSeq = $0 { return true }
            return false
        }

        // Should detect gaps at seq 2 and 4
        XCTAssertEqual(missingWarnings.count, 2)
        XCTAssertTrue(recovered.warnings.contains(.missingSeq(2)))
        XCTAssertTrue(recovered.warnings.contains(.missingSeq(4)))
    }

    // MARK: - Corrupt Line Handling

    func testCorruptLineHandling() throws {
        // Write a trace with a corrupt line in the middle
        let validEvent1 = makeEvent(seq: 1, type: .runStarted,
                                    payload: .runStarted(runID: "test-run", input: "Test"))
        let validEvent2 = makeEvent(seq: 2, type: .runCompleted,
                                    payload: .runCompleted(runID: "test-run", summary: nil))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let line1 = String(data: try encoder.encode(validEvent1), encoding: .utf8)!
        let corruptLine = "{ this is not valid json !!!"
        let line3 = String(data: try encoder.encode(validEvent2), encoding: .utf8)!

        try writeRawLines([line1, corruptLine, line3])

        let service = RunRecoveryService(baseDirectory: tempDir)
        let recovered = try service.recover(runID: "test-run")

        // Corrupt line should be skipped, valid events preserved
        XCTAssertEqual(recovered.events.count, 2)
        XCTAssertEqual(recovered.events[0].seq, 1)
        XCTAssertEqual(recovered.events[1].seq, 2)

        // Should have a corrupt line warning
        let corruptWarnings = recovered.warnings.filter {
            if case .corruptLine = $0 { return true }
            return false
        }
        XCTAssertEqual(corruptWarnings.count, 1)
    }

    // MARK: - Trace Not Found

    func testTraceNotFound() {
        let service = RunRecoveryService(baseDirectory: tempDir)

        XCTAssertThrowsError(try service.recover(runID: "nonexistent")) { error in
            guard let recoveryError = error as? RecoveryError else {
                XCTFail("Expected RecoveryError, got \(type(of: error))")
                return
            }
            if case .traceNotFound(let runID) = recoveryError {
                XCTAssertEqual(runID, "nonexistent")
            } else {
                XCTFail("Expected traceNotFound error")
            }
        }
    }

    // MARK: - Determinism: Same Trace -> Same Result 10 Times

    func testDeterminismSameTraceSameResult() throws {
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .sessionStarted,
                      payload: .sessionStarted(sessionID: "session-1", cwd: "/tmp")),
            makeEvent(seq: 2, type: .runStarted,
                      payload: .runStarted(runID: "test-run", input: "Determinism test")),
            makeEvent(seq: 3, type: .turnStarted,
                      payload: .turnStarted(turnID: "turn-1", input: "Determinism test")),
            makeEvent(seq: 4, type: .assistantDelta,
                      payload: .assistantDelta(text: "Hello ")),
            makeEvent(seq: 5, type: .assistantDelta,
                      payload: .assistantDelta(text: "world")),
            makeEvent(seq: 6, type: .toolCallRequested,
                      payload: .toolCall(name: "read_file", params: ["path": "main.swift"])),
            makeEvent(seq: 7, type: .toolCallCompleted,
                      payload: .toolCallCompleted(name: "read_file", result: "fn main() {}")),
            makeEvent(seq: 8, type: .turnCompleted,
                      payload: .turnCompleted(turnID: "turn-1")),
            makeEvent(seq: 9, type: .runCompleted,
                      payload: .runCompleted(runID: "test-run", summary: "Done"))
        ]

        try writeTrace(events)

        let service = RunRecoveryService(baseDirectory: tempDir)

        // Recover 10 times and verify all results are identical
        var results: [RecoveredRun] = []
        for _ in 0..<10 {
            let recovered = try service.recover(runID: "test-run")
            results.append(recovered)
        }

        // All runs must have the same status
        for (i, result) in results.enumerated() {
            XCTAssertEqual(result.run.status, results[0].run.status,
                           "Run status mismatch at iteration \(i)")
            XCTAssertEqual(result.run.input, results[0].run.input,
                           "Run input mismatch at iteration \(i)")
            XCTAssertEqual(result.run.resultSummary, results[0].run.resultSummary,
                           "Run resultSummary mismatch at iteration \(i)")
        }

        // All must have the same number of events
        let eventCounts = results.map(\.events.count)
        XCTAssertTrue(eventCounts.allSatisfy { $0 == eventCounts[0] })

        // All must have the same event IDs in the same order
        for (i, result) in results.enumerated() {
            let ids = result.events.map(\.id)
            let firstIds = results[0].events.map(\.id)
            XCTAssertEqual(ids, firstIds, "Event order mismatch at iteration \(i)")
        }

        // All must have the same snapshot status
        for (i, result) in results.enumerated() {
            XCTAssertEqual(result.snapshot.status, results[0].snapshot.status,
                           "Snapshot status mismatch at iteration \(i)")
        }

        // All must have the same timeline item count
        let timelineCounts = results.map(\.timeline.count)
        XCTAssertTrue(timelineCounts.allSatisfy { $0 == timelineCounts[0] })

        // All must have the same warnings
        for (i, result) in results.enumerated() {
            XCTAssertEqual(result.warnings.count, results[0].warnings.count,
                           "Warning count mismatch at iteration \(i)")
        }
    }

    // MARK: - Multiple Runs Recovery

    func testMultipleRunsInSameDirectory() throws {
        // Write traces for two different runs
        let events1: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .runStarted,
                      payload: .runStarted(runID: "run-1", input: "Task 1"),
                      runID: "run-1"),
            makeEvent(seq: 2, type: .runCompleted,
                      payload: .runCompleted(runID: "run-1", summary: "Done 1"),
                      runID: "run-1")
        ]
        let events2: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .runStarted,
                      payload: .runStarted(runID: "run-2", input: "Task 2"),
                      runID: "run-2"),
            makeEvent(seq: 2, type: .runFailed,
                      payload: .runFailed(runID: "run-2", error: "Failed 2"),
                      runID: "run-2")
        ]

        try writeTrace(events1, runID: "run-1")
        try writeTrace(events2, runID: "run-2")

        let service = RunRecoveryService(baseDirectory: tempDir)

        let recovered1 = try service.recover(runID: "run-1")
        let recovered2 = try service.recover(runID: "run-2")

        XCTAssertEqual(recovered1.run.status, .completed)
        XCTAssertEqual(recovered1.run.input, "Task 1")

        XCTAssertEqual(recovered2.run.status, .failed)
        XCTAssertEqual(recovered2.run.input, "Task 2")
        XCTAssertEqual(recovered2.run.resultSummary, "Failed 2")
    }

    // MARK: - Run with Approval Flow

    func testRunWithApprovalFlow() throws {
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .runStarted,
                      payload: .runStarted(runID: "test-run", input: "Delete files")),
            makeEvent(seq: 2, type: .turnStarted,
                      payload: .turnStarted(turnID: "turn-1", input: "Delete files")),
            makeEvent(seq: 3, type: .approvalRequested,
                      payload: .approvalRequested(requestID: 1, tool: "rm", command: "rm -rf /tmp/junk", riskLevel: "high")),
            makeEvent(seq: 4, type: .approvalResolved,
                      payload: .approvalResolved(requestID: 1, decision: "accept")),
            makeEvent(seq: 5, type: .runCompleted,
                      payload: .runCompleted(runID: "test-run", summary: "Files deleted"))
        ]

        try writeTrace(events)

        let service = RunRecoveryService(baseDirectory: tempDir)
        let recovered = try service.recover(runID: "test-run")

        XCTAssertEqual(recovered.run.status, .completed)

        // Timeline should have approval items
        let approvalItems = recovered.timeline.filter { $0.type == .approval }
        XCTAssertEqual(approvalItems.count, 2) // requested + resolved
    }

    // MARK: - Run with Process Exit

    func testRunWithProcessExit() throws {
        let events: [RuntimeEvent] = [
            makeEvent(seq: 1, type: .runStarted,
                      payload: .runStarted(runID: "test-run", input: "Task")),
            makeEvent(seq: 2, type: .turnStarted,
                      payload: .turnStarted(turnID: "turn-1", input: "Task")),
            makeEvent(seq: 3, type: .exited,
                      payload: .exited(code: 1))
        ]

        try writeTrace(events)

        let service = RunRecoveryService(baseDirectory: tempDir)
        let recovered = try service.recover(runID: "test-run")

        // Process exit should mark the run as failed
        XCTAssertEqual(recovered.run.status, .failed)
        XCTAssertEqual(recovered.run.resultSummary, "Process exited unexpectedly")

        let incompleteWarnings = recovered.warnings.filter {
            if case .incompleteRun = $0 { return true }
            return false
        }
        XCTAssertFalse(incompleteWarnings.isEmpty)
    }

    // MARK: - Multiple Corrupt Lines

    func testMultipleCorruptLines() throws {
        let validEvent = makeEvent(seq: 1, type: .runStarted,
                                   payload: .runStarted(runID: "test-run", input: "Test"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let validLine = String(data: try encoder.encode(validEvent), encoding: .utf8)!

        try writeRawLines([
            validLine,
            "not json 1",
            "not json 2",
            "not json 3"
        ])

        let service = RunRecoveryService(baseDirectory: tempDir)
        let recovered = try service.recover(runID: "test-run")

        XCTAssertEqual(recovered.events.count, 1)

        let corruptWarnings = recovered.warnings.filter {
            if case .corruptLine = $0 { return true }
            return false
        }
        XCTAssertEqual(corruptWarnings.count, 3)
    }
}
