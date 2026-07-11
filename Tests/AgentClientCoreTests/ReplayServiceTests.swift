import XCTest
@testable import AgentClientCore

/// Tests for TraceReader, SnapshotRebuilder, and ReplayService.
///
/// These tests verify that `trace.jsonl` is a sufficient source of truth
/// to fully reconstruct Agent state — no snapshot files required.
final class ReplayServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReplayServiceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - TraceReader

    /// TraceReader reads all events from a trace file in seq order.
    func testTraceReader_readsAllEventsInOrder() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")
        let writer = TraceWriter(runID: "reader-test", baseDirectory: tempDir)
        for (i, event) in events.enumerated() {
            try writer.append(event.withSeq(UInt64(i + 1)))
        }

        let reader = TraceReader(runID: "reader-test", baseDirectory: tempDir)
        XCTAssertTrue(reader.exists)

        let result = try reader.readAll()
        XCTAssertEqual(result.events.count, events.count)
        XCTAssertEqual(result.skipped, 0)

        // Verify seq ordering
        for i in 1..<result.events.count {
            XCTAssertLessThanOrEqual(
                result.events[i - 1].seq ?? 0,
                result.events[i].seq ?? 0,
                "Events should be sorted by seq"
            )
        }
    }

    /// TraceReader returns empty result for missing file.
    func testTraceReader_missingFile_returnsEmpty() throws {
        let reader = TraceReader(runID: "nonexistent", baseDirectory: tempDir)
        XCTAssertFalse(reader.exists)

        let result = try reader.readAll()
        XCTAssertTrue(result.events.isEmpty)
        XCTAssertEqual(result.skipped, 0)
    }

    /// TraceReader read(afterSeq:) filters correctly.
    func testTraceReader_afterSeq() throws {
        let events = try FixtureLoader.loadFixture("tool_failed")
        let writer = TraceWriter(runID: "seq-test", baseDirectory: tempDir)
        for (i, event) in events.enumerated() {
            try writer.append(event.withSeq(UInt64(i + 1)))
        }

        let reader = TraceReader(runID: "seq-test", baseDirectory: tempDir)
        let after3 = try reader.read(afterSeq: 3)
        XCTAssertEqual(after3.count, events.count - 3)
        XCTAssertEqual(after3.first?.seq, 4)
    }

    /// TraceReader preserves all event fields through round-trip.
    func testTraceReader_preservesFields() throws {
        let original = RuntimeEvent(
            id: "field-test", seq: 1, version: 1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            sessionID: "s1", runID: "r1",
            runtime: .claudeCode, type: .turnStarted,
            payload: .turnStarted(turnID: "t1", input: "fix bug")
        )

        let writer = TraceWriter(runID: "fields", baseDirectory: tempDir)
        try writer.append(original)

        let reader = TraceReader(runID: "fields", baseDirectory: tempDir)
        let result = try reader.readAll()
        XCTAssertEqual(result.events.count, 1)

        let read = result.events[0]
        XCTAssertEqual(read.id, "field-test")
        XCTAssertEqual(read.seq, 1)
        XCTAssertEqual(read.version, 1)
        XCTAssertEqual(read.sessionID, "s1")
        XCTAssertEqual(read.runID, "r1")
        XCTAssertEqual(read.runtime, .claudeCode)
        XCTAssertEqual(read.type, .turnStarted)
        XCTAssertEqual(read.payload, .turnStarted(turnID: "t1", input: "fix bug"))
    }

    // MARK: - SnapshotRebuilder

    /// Rebuild normal coding run → completed snapshot with file changes.
    func testSnapshotRebuilder_normalCodingRun() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")
        let snapshot = SnapshotRebuilder.rebuild(from: events)

        XCTAssertEqual(snapshot.threadID, "session-001")
        XCTAssertEqual(snapshot.status, .completed)
        XCTAssertFalse(snapshot.completedTurns.isEmpty)
        XCTAssertNil(snapshot.lastError)

        // File changes recorded
        XCTAssertFalse(snapshot.fileChanges.isEmpty)

        // User message captured
        let lastTurn = snapshot.completedTurns.last
        XCTAssertEqual(lastTurn?.userMessage, "修复登录页面的崩溃问题")
        XCTAssertTrue(lastTurn?.isCompleted ?? false)
    }

    /// Rebuild approval rejected → snapshot shows rejection and error.
    func testSnapshotRebuilder_approvalRejected() throws {
        let events = try FixtureLoader.loadFixture("approval_rejected")
        let snapshot = SnapshotRebuilder.rebuild(from: events)

        XCTAssertEqual(snapshot.threadID, "session-002")
        XCTAssertNotNil(snapshot.lastError)
        XCTAssertTrue(snapshot.lastError?.message.contains("用户拒绝") ?? false)

        // Approval was resolved
        let approval = snapshot.pendingApprovals.values.first
        XCTAssertNotNil(approval)
        XCTAssertEqual(approval?.decision, "reject")
    }

    /// Rebuild tool failed → snapshot shows error with code.
    func testSnapshotRebuilder_toolFailed() throws {
        let events = try FixtureLoader.loadFixture("tool_failed")
        let snapshot = SnapshotRebuilder.rebuild(from: events)

        XCTAssertEqual(snapshot.threadID, "session-003")
        XCTAssertNotNil(snapshot.lastError)
        XCTAssertEqual(snapshot.lastError?.code, "TEST_FAILURE")
    }

    /// RebuildWithTimeline returns both snapshot and timeline.
    func testSnapshotRebuilder_withTimeline() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")
        let (snapshot, timeline) = SnapshotRebuilder.rebuildWithTimeline(from: events)

        // Snapshot
        XCTAssertEqual(snapshot.status, .completed)

        // Timeline has meaningful items
        XCTAssertGreaterThanOrEqual(timeline.count, 3)
        XCTAssertEqual(timeline.first?.type, .userMessage)
        XCTAssertEqual(timeline.last?.type, .finalResult)
    }

    /// Empty events → empty snapshot.
    func testSnapshotRebuilder_emptyEvents() {
        let snapshot = SnapshotRebuilder.rebuild(from: [])
        XCTAssertNil(snapshot.threadID)
        XCTAssertEqual(snapshot.status, .idle)
        XCTAssertTrue(snapshot.completedTurns.isEmpty)
    }

    // MARK: - ReplayService

    /// ReplayService.rebuild() reads trace and returns correct snapshot.
    func testReplayService_rebuild_normalCodingRun() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")
        let writer = TraceWriter(runID: "svc-test", baseDirectory: tempDir)
        for (i, event) in events.enumerated() {
            try writer.append(event.withSeq(UInt64(i + 1)))
        }

        let service = ReplayService(baseDirectory: tempDir)
        let snapshot = try service.rebuild(runID: "svc-test")

        XCTAssertEqual(snapshot.threadID, "session-001")
        XCTAssertEqual(snapshot.status, .completed)
        XCTAssertFalse(snapshot.completedTurns.isEmpty)
    }

    /// ReplayService.rebuild() throws for missing trace.
    func testReplayService_rebuild_missingTrace() {
        let service = ReplayService(baseDirectory: tempDir)

        XCTAssertThrowsError(try service.rebuild(runID: "nonexistent")) { error in
            guard case ReplayError.traceNotFound = error else {
                XCTFail("Expected ReplayError.traceNotFound, got \(error)")
                return
            }
        }
    }

    /// ReplayService.rebuildWithTimeline() returns both snapshot and timeline.
    func testReplayService_rebuildWithTimeline() throws {
        let events = try FixtureLoader.loadFixture("approval_rejected")
        let writer = TraceWriter(runID: "svc-timeline", baseDirectory: tempDir)
        for (i, event) in events.enumerated() {
            try writer.append(event.withSeq(UInt64(i + 1)))
        }

        let service = ReplayService(baseDirectory: tempDir)
        let (snapshot, timeline) = try service.rebuildWithTimeline(runID: "svc-timeline")

        XCTAssertNotNil(snapshot.lastError)
        XCTAssertGreaterThanOrEqual(timeline.count, 2)
    }

    /// ReplayService.availableRuns() lists runs with trace files.
    func testReplayService_availableRuns() throws {
        // Create two trace files
        let events = try FixtureLoader.loadFixture("tool_failed")
        for runID in ["run-alpha", "run-beta"] {
            let writer = TraceWriter(runID: runID, baseDirectory: tempDir)
            for (i, event) in events.enumerated() {
                try writer.append(event.withSeq(UInt64(i + 1)))
            }
        }

        let service = ReplayService(baseDirectory: tempDir)
        let runs = service.availableRuns()
        XCTAssertEqual(runs.count, 2)
        XCTAssertTrue(runs.contains("run-alpha"))
        XCTAssertTrue(runs.contains("run-beta"))
    }

    /// ReplayService.availableRuns() returns empty for no traces.
    func testReplayService_availableRuns_empty() {
        let emptyDir = tempDir.appendingPathComponent("empty")
        try? FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        let service = ReplayService(baseDirectory: emptyDir)
        XCTAssertTrue(service.availableRuns().isEmpty)
    }

    // MARK: - Scenario A: Full Normal Execution

    /// End-to-end: write fixture to trace → replay → verify snapshot matches.
    ///
    /// This is the core guarantee: `trace.jsonl` is the sole source of truth.
    /// No snapshot file, no live runtime — just the trace.
    func testScenarioA_normalExecution_traceIsSoleSourceOfTruth() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")

        // Write to trace
        let writer = TraceWriter(runID: "scenario-a", baseDirectory: tempDir)
        for (i, event) in events.enumerated() {
            try writer.append(event.withSeq(UInt64(i + 1)))
        }

        // Rebuild from trace — no snapshot file exists
        let service = ReplayService(baseDirectory: tempDir)
        let snapshot = try service.rebuild(runID: "scenario-a")

        // Session
        XCTAssertEqual(snapshot.threadID, "session-001")
        XCTAssertNotNil(snapshot.cwd)

        // Status
        XCTAssertEqual(snapshot.status, .completed)

        // Turn
        XCTAssertEqual(snapshot.completedTurns.count, 1)
        let turn = snapshot.completedTurns[0]
        XCTAssertEqual(turn.id, "turn-001")
        XCTAssertTrue(turn.isCompleted)
        XCTAssertEqual(turn.userMessage, "修复登录页面的崩溃问题")
        XCTAssertTrue(turn.assistantText.contains("修复完成"))

        // File changes
        let changedPaths = snapshot.fileChanges.values.compactMap(\.path)
        XCTAssertTrue(changedPaths.contains { $0.contains("LoginView.swift") })

        // Approvals resolved
        let pendingApprovals = snapshot.pendingApprovals.values.filter(\.isPending)
        XCTAssertTrue(pendingApprovals.isEmpty, "All approvals should be resolved")

        // No errors
        XCTAssertNil(snapshot.lastError)

        // Timeline also works
        let (rebuiltSnapshot, timeline) = try service.rebuildWithTimeline(runID: "scenario-a")
        XCTAssertEqual(rebuiltSnapshot.threadID, snapshot.threadID)

        let userMessages = timeline.filter { $0.type == .userMessage }
        XCTAssertFalse(userMessages.isEmpty)
        XCTAssertEqual(userMessages.first?.data, .userMessage(text: "修复登录页面的崩溃问题"))

        let toolCalls = timeline.filter { $0.type == .toolCall }
        XCTAssertGreaterThan(toolCalls.count, 0)
    }

    // MARK: - Scenario B: Trace-Only Recovery (no snapshot file)

    /// Simulate: snapshot file deleted, only trace.jsonl survives.
    /// Verify we can fully recover state from trace alone.
    func testScenarioB_traceOnlyRecovery() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")

        // Phase 1: Write trace and build snapshot from live events
        let writer = TraceWriter(runID: "scenario-b", baseDirectory: tempDir)
        for (i, event) in events.enumerated() {
            try writer.append(event.withSeq(UInt64(i + 1)))
        }

        // Build snapshot from live events (simulates "before crash")
        let liveSnapshot = SnapshotRebuilder.rebuild(from: events)

        // Phase 2: "Crash" — simulate that only trace.jsonl survives.
        // No snapshot file, no EventStore, no live runtime.

        // Phase 3: Recover from trace only
        let service = ReplayService(baseDirectory: tempDir)
        let recoveredSnapshot = try service.rebuild(runID: "scenario-b")

        // Verify recovered state matches live state
        XCTAssertEqual(recoveredSnapshot.threadID, liveSnapshot.threadID)
        XCTAssertEqual(recoveredSnapshot.status, liveSnapshot.status)
        XCTAssertEqual(recoveredSnapshot.cwd, liveSnapshot.cwd)
        XCTAssertEqual(recoveredSnapshot.completedTurns.count, liveSnapshot.completedTurns.count)
        XCTAssertEqual(recoveredSnapshot.fileChanges.count, liveSnapshot.fileChanges.count)
        XCTAssertEqual(recoveredSnapshot.pendingApprovals.count, liveSnapshot.pendingApprovals.count)
        XCTAssertNil(recoveredSnapshot.lastError)

        // Verify turn details match
        let recoveredTurn = recoveredSnapshot.completedTurns.last
        let liveTurn = liveSnapshot.completedTurns.last
        XCTAssertEqual(recoveredTurn?.id, liveTurn?.id)
        XCTAssertEqual(recoveredTurn?.userMessage, liveTurn?.userMessage)
        XCTAssertEqual(recoveredTurn?.assistantText, liveTurn?.assistantText)
        XCTAssertEqual(recoveredTurn?.isCompleted, liveTurn?.isCompleted)

        // Verify file changes match
        let recoveredFiles = Set(recoveredSnapshot.fileChanges.values.compactMap(\.path))
        let liveFiles = Set(liveSnapshot.fileChanges.values.compactMap(\.path))
        XCTAssertEqual(recoveredFiles, liveFiles)
    }

    /// Trace-only recovery for approval flow.
    func testScenarioB_traceOnlyRecovery_approvalFlow() throws {
        let events = try FixtureLoader.loadFixture("approval_rejected")

        let writer = TraceWriter(runID: "scenario-b-approval", baseDirectory: tempDir)
        for (i, event) in events.enumerated() {
            try writer.append(event.withSeq(UInt64(i + 1)))
        }

        let liveSnapshot = SnapshotRebuilder.rebuild(from: events)
        let service = ReplayService(baseDirectory: tempDir)
        let recovered = try service.rebuild(runID: "scenario-b-approval")

        XCTAssertEqual(recovered.threadID, liveSnapshot.threadID)
        XCTAssertEqual(recovered.lastError?.message, liveSnapshot.lastError?.message)

        // Approval state recovered
        let recoveredApproval = recovered.pendingApprovals.values.first
        let liveApproval = liveSnapshot.pendingApprovals.values.first
        XCTAssertEqual(recoveredApproval?.decision, liveApproval?.decision)
        XCTAssertEqual(recoveredApproval?.isPending, liveApproval?.isPending)
    }

    /// Trace-only recovery for tool failure.
    func testScenarioB_traceOnlyRecovery_toolFailed() throws {
        let events = try FixtureLoader.loadFixture("tool_failed")

        let writer = TraceWriter(runID: "scenario-b-toolfail", baseDirectory: tempDir)
        for (i, event) in events.enumerated() {
            try writer.append(event.withSeq(UInt64(i + 1)))
        }

        let liveSnapshot = SnapshotRebuilder.rebuild(from: events)
        let service = ReplayService(baseDirectory: tempDir)
        let recovered = try service.rebuild(runID: "scenario-b-toolfail")

        XCTAssertEqual(recovered.threadID, liveSnapshot.threadID)
        XCTAssertEqual(recovered.lastError?.message, liveSnapshot.lastError?.message)
        XCTAssertEqual(recovered.lastError?.code, liveSnapshot.lastError?.code)
    }

    // MARK: - Crash Recovery (write → deallocate → new reader)

    /// Simulate crash: writer writes trace, app crashes, new reader recovers.
    func testCrashRecovery_writerDies_readerRecovers() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")

        // Writer writes and "crashes" (deallocated)
        do {
            let writer = TraceWriter(runID: "crash-sim", baseDirectory: tempDir)
            for (i, event) in events.enumerated() {
                try writer.append(event.withSeq(UInt64(i + 1)))
            }
        }

        // New reader on fresh process
        let reader = TraceReader(runID: "crash-sim", baseDirectory: tempDir)
        let result = try reader.readAll()
        XCTAssertEqual(result.events.count, events.count)

        // Rebuild snapshot from recovered trace
        let snapshot = SnapshotRebuilder.rebuild(from: result.events)
        XCTAssertEqual(snapshot.threadID, "session-001")
        XCTAssertEqual(snapshot.status, .completed)
    }
}
