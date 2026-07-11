import XCTest
@testable import AgentClientCore

// MARK: - RunLifecycleManager Tests

final class RunLifecycleManagerTests: XCTestCase {

    // MARK: - Run Creation

    func testRunStartedCreatesNewRun() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        let event = makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: "Fix bug"))
        let run = manager.apply(event: event)

        XCTAssertNotNil(run)
        XCTAssertEqual(run?.id, "run-1")
        XCTAssertEqual(run?.status, .running)
        XCTAssertEqual(run?.input, "Fix bug")
        XCTAssertEqual(run?.sessionID, "s1")
        XCTAssertEqual(run?.runtime, .codex)
        XCTAssertEqual(run?.provider, "Codex CLI")
    }

    func testRunStartedUsesEventSessionID() {
        var manager = RunLifecycleManager(sessionID: "default", runtime: .codex)

        let event = RuntimeEvent(
            sessionID: "custom-session",
            runID: "run-1",
            runtime: .codex,
            type: .runStarted,
            payload: .runStarted(runID: "run-1", input: nil)
        )
        let run = manager.apply(event: event)

        XCTAssertEqual(run?.sessionID, "custom-session")
    }

    // MARK: - Approval Flow

    func testApprovalRequestedTransitionsToWaitingApproval() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: nil)))

        let approvalEvent = RuntimeEvent(
            runID: "run-1",
            runtime: .codex,
            type: .approvalRequested,
            payload: .approvalRequested(requestID: 1, tool: "bash", command: "rm -rf /tmp", riskLevel: "high")
        )
        let run = manager.apply(event: approvalEvent)

        XCTAssertEqual(run?.status, .waitingApproval)
        XCTAssertEqual(run?.approvalCount, 1)
    }

    func testApprovalResolvedTransitionsBackToRunning() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: nil)))
        manager.apply(event: RuntimeEvent(
            runID: "run-1",
            runtime: .codex,
            type: .approvalRequested,
            payload: .approvalRequested(requestID: 1, tool: "bash", command: nil, riskLevel: nil)
        ))

        let resolveEvent = RuntimeEvent(
            runID: "run-1",
            runtime: .codex,
            type: .approvalResolved,
            payload: .approvalResolved(requestID: 1, decision: "approve")
        )
        let run = manager.apply(event: resolveEvent)

        XCTAssertEqual(run?.status, .running)
    }

    // MARK: - Completion

    func testRunCompleted() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: nil)))

        let event = makeEvent(type: .runCompleted, payload: .runCompleted(runID: "run-1", summary: "All done"))
        let run = manager.apply(event: event)

        XCTAssertEqual(run?.status, .completed)
        XCTAssertEqual(run?.resultSummary, "All done")
        XCTAssertNotNil(run?.finishedAt)
        XCTAssertNil(manager.currentRun) // cleared after terminal
    }

    func testRunFailed() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: nil)))

        let event = makeEvent(type: .runFailed, payload: .runFailed(runID: "run-1", error: "API error"))
        let run = manager.apply(event: event)

        XCTAssertEqual(run?.status, .failed)
        XCTAssertEqual(run?.errorSummary, "API error")
        XCTAssertNil(manager.currentRun)
    }

    func testRunCancelled() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: nil)))

        let event = makeEvent(type: .runCancelled, payload: .runCancelled(runID: "run-1"))
        let run = manager.apply(event: event)

        XCTAssertEqual(run?.status, .cancelled)
        XCTAssertNil(manager.currentRun)
    }

    // MARK: - Counter Tracking

    func testToolCallIncrementsCounter() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: nil)))

        let toolEvent = RuntimeEvent(
            runID: "run-1",
            runtime: .codex,
            type: .toolCallRequested,
            payload: .toolCall(name: "bash", params: ["command": "ls"])
        )
        manager.apply(event: toolEvent)
        manager.apply(event: toolEvent)

        XCTAssertEqual(manager.currentRun?.toolCallCount, 2)
    }

    func testFileChangeIncrementsCounter() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: nil)))

        let fileEvent = RuntimeEvent(
            runID: "run-1",
            runtime: .codex,
            type: .fileChangeDetected,
            payload: .fileChange(path: "/tmp/foo.swift", changeKind: "modified")
        )
        manager.apply(event: fileEvent)
        manager.apply(event: fileEvent)
        manager.apply(event: fileEvent)

        XCTAssertEqual(manager.currentRun?.filesChangedCount, 3)
    }

    func testApprovalCountAccumulates() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: nil)))

        // First approval
        manager.apply(event: RuntimeEvent(
            runID: "run-1", runtime: .codex, type: .approvalRequested,
            payload: .approvalRequested(requestID: 1, tool: "bash", command: nil, riskLevel: nil)
        ))
        manager.apply(event: RuntimeEvent(
            runID: "run-1", runtime: .codex, type: .approvalResolved,
            payload: .approvalResolved(requestID: 1, decision: "approve")
        ))

        // Second approval
        manager.apply(event: RuntimeEvent(
            runID: "run-1", runtime: .codex, type: .approvalRequested,
            payload: .approvalRequested(requestID: 2, tool: "bash", command: nil, riskLevel: nil)
        ))

        XCTAssertEqual(manager.currentRun?.approvalCount, 2)
    }

    // MARK: - Model Tracking

    func testSettingsUpdatedSetsModel() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: nil)))

        let settingsEvent = RuntimeEvent(
            runID: "run-1",
            runtime: .codex,
            type: .settingsUpdated,
            payload: .settingsUpdated(model: "gpt-4o", effort: "high")
        )
        manager.apply(event: settingsEvent)

        XCTAssertEqual(manager.currentRun?.model, "gpt-4o")
    }

    // MARK: - Interrupted

    func testExitedMarksActiveRunAsInterrupted() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: nil)))

        let exitEvent = RuntimeEvent(
            runID: "run-1",
            runtime: .codex,
            type: .exited,
            payload: .exited(code: 1)
        )
        let run = manager.apply(event: exitEvent)

        XCTAssertEqual(run?.status, .interrupted)
        XCTAssertNotNil(run?.finishedAt)
        XCTAssertNil(manager.currentRun)
    }

    func testExitedDoesNotAffectTerminalRun() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: nil)))
        manager.apply(event: makeEvent(type: .runCompleted, payload: .runCompleted(runID: "run-1", summary: nil)))

        let exitEvent = RuntimeEvent(
            runID: "run-1",
            runtime: .codex,
            type: .exited,
            payload: .exited(code: 0)
        )
        let run = manager.apply(event: exitEvent)

        XCTAssertNil(run) // Already completed, no change
    }

    func testMarkInterruptedManually() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: nil)))

        let run = manager.markInterrupted()

        XCTAssertNotNil(run)
        XCTAssertEqual(run?.status, .interrupted)
        XCTAssertNil(manager.currentRun)
    }

    func testMarkInterruptedReturnsNilWhenNoActiveRun() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        let run = manager.markInterrupted()
        XCTAssertNil(run)
    }

    // MARK: - RunID Mismatch

    func testEventsIgnoredForWrongRunID() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: nil)))

        let wrongEvent = makeEvent(type: .runCompleted, payload: .runCompleted(runID: "run-2", summary: nil))
        let run = manager.apply(event: wrongEvent)

        XCTAssertNil(run)
        XCTAssertNotNil(manager.currentRun) // still active
    }

    // MARK: - Full Lifecycle

    func testFullLifecycleHappyPath() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .claudeCode)

        // Start
        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: "Build feature")))
        XCTAssertEqual(manager.currentRun?.status, .running)

        // Tool call
        manager.apply(event: RuntimeEvent(
            runID: "run-1", runtime: .claudeCode, type: .toolCallRequested,
            payload: .toolCall(name: "bash", params: nil)
        ))

        // File change
        manager.apply(event: RuntimeEvent(
            runID: "run-1", runtime: .claudeCode, type: .fileChangeDetected,
            payload: .fileChange(path: "/src/main.swift", changeKind: "created")
        ))

        // Approval cycle
        manager.apply(event: RuntimeEvent(
            runID: "run-1", runtime: .claudeCode, type: .approvalRequested,
            payload: .approvalRequested(requestID: 1, tool: "bash", command: "swift build", riskLevel: nil)
        ))
        XCTAssertEqual(manager.currentRun?.status, .waitingApproval)

        manager.apply(event: RuntimeEvent(
            runID: "run-1", runtime: .claudeCode, type: .approvalResolved,
            payload: .approvalResolved(requestID: 1, decision: "approve")
        ))
        XCTAssertEqual(manager.currentRun?.status, .running)

        // Complete
        let completed = manager.apply(event: makeEvent(
            type: .runCompleted,
            payload: .runCompleted(runID: "run-1", summary: "Feature built")
        ))

        XCTAssertEqual(completed?.status, .completed)
        XCTAssertEqual(completed?.toolCallCount, 1)
        XCTAssertEqual(completed?.filesChangedCount, 1)
        XCTAssertEqual(completed?.approvalCount, 1)
        XCTAssertEqual(completed?.resultSummary, "Feature built")
        XCTAssertNil(manager.currentRun)
    }

    // MARK: - Multiple Runs

    func testMultipleSequentialRuns() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        // First run
        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-1", input: "Task 1")))
        let r1 = manager.apply(event: makeEvent(type: .runCompleted, payload: .runCompleted(runID: "run-1", summary: nil)))

        // Second run
        manager.apply(event: makeEvent(type: .runStarted, payload: .runStarted(runID: "run-2", input: "Task 2")))
        let r2 = manager.apply(event: makeEvent(type: .runFailed, payload: .runFailed(runID: "run-2", error: "boom")))

        XCTAssertEqual(r1?.status, .completed)
        XCTAssertEqual(r2?.status, .failed)
    }

    // MARK: - Non-Run Events

    func testNonRunEventsReturnNil() {
        var manager = RunLifecycleManager(sessionID: "s1", runtime: .codex)

        let events: [(RuntimeEventType, RuntimeEventPayload)] = [
            (.turnStarted, .turnStarted(turnID: "t1", input: nil)),
            (.turnCompleted, .turnCompleted(turnID: "t1")),
            (.assistantDelta, .assistantDelta(text: "hello")),
            (.sessionStarted, .sessionStarted(sessionID: "s1", cwd: nil)),
        ]

        for (type, payload) in events {
            let event = RuntimeEvent(runtime: .codex, type: type, payload: payload)
            XCTAssertNil(manager.apply(event: event), "Event type \(type) should return nil")
        }
    }
}

// MARK: - InMemoryRunRepository Tests

final class InMemoryRunRepositoryTests: XCTestCase {
    private var repo: InMemoryRunRepository!

    override func setUp() {
        super.setUp()
        repo = InMemoryRunRepository()
    }

    override func tearDown() {
        repo = nil
        super.tearDown()
    }

    // MARK: - Create / Get

    func testCreateAndGetRun() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex, input: "Hello")
        try repo.createRun(run, in: "s1")

        let loaded = try repo.getRun(runID: "run-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, "run-1")
        XCTAssertEqual(loaded?.input, "Hello")
    }

    func testGetNonexistentReturnsNil() throws {
        let loaded = try repo.getRun(runID: "nonexistent")
        XCTAssertNil(loaded)
    }

    func testCreateDuplicateThrows() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        try repo.createRun(run, in: "s1")

        XCTAssertThrowsError(try repo.createRun(run, in: "s1"))
    }

    // MARK: - Update

    func testUpdateExistingRun() throws {
        var run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex, input: "original")
        try repo.createRun(run, in: "s1")

        run.start()
        run.complete(summary: "Done")
        try repo.updateRun(run)

        let loaded = try repo.getRun(runID: "run-1")
        XCTAssertEqual(loaded?.status, .completed)
        XCTAssertEqual(loaded?.resultSummary, "Done")
    }

    func testUpdateNonexistentThrows() {
        let run = AgentRun(id: "missing", sessionID: "s1", runtime: .codex)
        XCTAssertThrowsError(try repo.updateRun(run))
    }

    // MARK: - List by Session

    func testListRunsBySession() throws {
        let run1 = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        let run2 = AgentRun(id: "run-2", sessionID: "s1", runtime: .codex)
        let run3 = AgentRun(id: "run-3", sessionID: "s2", runtime: .codex)

        try repo.createRun(run1, in: "s1")
        try repo.createRun(run2, in: "s1")
        try repo.createRun(run3, in: "s2")

        let s1Runs = try repo.listRuns(sessionID: "s1")
        XCTAssertEqual(s1Runs.count, 2)

        let s2Runs = try repo.listRuns(sessionID: "s2")
        XCTAssertEqual(s2Runs.count, 1)
    }

    func testListRunsSortedByCreatedAt() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_000_001)

        let run1 = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex, createdAt: t1)
        let run2 = AgentRun(id: "run-2", sessionID: "s1", runtime: .codex, createdAt: t0)

        try repo.createRun(run1, in: "s1")
        try repo.createRun(run2, in: "s1")

        let runs = try repo.listRuns(sessionID: "s1")
        XCTAssertEqual(runs[0].id, "run-2") // t0 first
        XCTAssertEqual(runs[1].id, "run-1")
    }

    func testListRunsEmptyForUnknownSession() throws {
        let runs = try repo.listRuns(sessionID: "unknown")
        XCTAssertTrue(runs.isEmpty)
    }

    // MARK: - List by Workspace

    func testListRunsByWorkspace() throws {
        let run1 = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        let run2 = AgentRun(id: "run-2", sessionID: "s2", runtime: .codex)

        try repo.createRun(run1, in: "s1")
        try repo.createRun(run2, in: "s2")

        let all = try repo.listRuns(workspace: "/some/path")
        XCTAssertEqual(all.count, 2)
    }
}

// MARK: - FileRunRepository Tests

final class FileRunRepositoryTests: XCTestCase {
    private var repo: FileRunRepository!
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunRepositoryTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        repo = FileRunRepository(baseDirectory: tempDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        repo = nil
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Create / Get

    func testCreateAndGetRun() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex, input: "Hello")
        try repo.createRun(run, in: "s1")

        let loaded = try repo.getRun(runID: "run-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.id, "run-1")
        XCTAssertEqual(loaded?.input, "Hello")
    }

    func testCreateCreatesDirectoryStructure() throws {
        let run = AgentRun(id: "run-abc", sessionID: "s1", runtime: .codex)
        try repo.createRun(run, in: "s1")

        let runDir = tempDirectory
            .appendingPathComponent("s1")
            .appendingPathComponent("runs")
            .appendingPathComponent("run-abc")
        let metadataFile = runDir.appendingPathComponent("metadata.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: runDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataFile.path))
    }

    func testCreateCreatesIndexFile() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        try repo.createRun(run, in: "s1")

        let indexFile = tempDirectory
            .appendingPathComponent("s1")
            .appendingPathComponent("runs")
            .appendingPathComponent("index.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: indexFile.path))
    }

    func testCreateIsAtomic() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        try repo.createRun(run, in: "s1")

        let runDir = tempDirectory
            .appendingPathComponent("s1")
            .appendingPathComponent("runs")
            .appendingPathComponent("run-1")
        let contents = try FileManager.default.contentsOfDirectory(atPath: runDir.path)
        XCTAssertEqual(contents, ["metadata.json"])
    }

    func testCreateDuplicateThrows() throws {
        let run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        try repo.createRun(run, in: "s1")

        XCTAssertThrowsError(try repo.createRun(run, in: "s1"))
    }

    // MARK: - Update

    func testUpdateModifiesExistingRun() throws {
        var run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex, input: "original")
        try repo.createRun(run, in: "s1")

        run.start()
        run.complete(summary: "Done")
        try repo.updateRun(run)

        let loaded = try repo.getRun(runID: "run-1")
        XCTAssertEqual(loaded?.status, .completed)
        XCTAssertEqual(loaded?.resultSummary, "Done")
    }

    func testUpdateThrowsForMissingRun() {
        let run = AgentRun(id: "missing", sessionID: "s1", runtime: .codex)
        XCTAssertThrowsError(try repo.updateRun(run))
    }

    func testUpdateRefreshesIndex() throws {
        var run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        try repo.createRun(run, in: "s1")

        run.start()
        try repo.updateRun(run)

        let runs = try repo.listRuns(sessionID: "s1")
        XCTAssertEqual(runs.first?.status, .running)
    }

    // MARK: - List

    func testListRunsBySession() throws {
        let run1 = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        let run2 = AgentRun(id: "run-2", sessionID: "s1", runtime: .codex)
        let run3 = AgentRun(id: "run-3", sessionID: "s2", runtime: .codex)

        try repo.createRun(run1, in: "s1")
        try repo.createRun(run2, in: "s1")
        try repo.createRun(run3, in: "s2")

        let s1Runs = try repo.listRuns(sessionID: "s1")
        XCTAssertEqual(s1Runs.count, 2)
        XCTAssertTrue(s1Runs.allSatisfy { $0.sessionID == "s1" })

        let s2Runs = try repo.listRuns(sessionID: "s2")
        XCTAssertEqual(s2Runs.count, 1)
    }

    func testListRunsSortedByCreatedAt() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_000_001)

        let run1 = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex, createdAt: t1)
        let run2 = AgentRun(id: "run-2", sessionID: "s1", runtime: .codex, createdAt: t0)

        try repo.createRun(run1, in: "s1")
        try repo.createRun(run2, in: "s1")

        let runs = try repo.listRuns(sessionID: "s1")
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs[0].id, "run-2")
        XCTAssertEqual(runs[1].id, "run-1")
    }

    func testListRunsEmptyForNoSessions() throws {
        let runs = try repo.listRuns(sessionID: "s1")
        XCTAssertTrue(runs.isEmpty)
    }

    // MARK: - List by Workspace

    func testListRunsByWorkspace() throws {
        let run1 = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        let run2 = AgentRun(id: "run-2", sessionID: "s2", runtime: .codex)

        try repo.createRun(run1, in: "s1")
        try repo.createRun(run2, in: "s2")

        let all = try repo.listRuns(workspace: "/some/path")
        XCTAssertEqual(all.count, 2)
    }

    // MARK: - Metadata Round-Trip

    func testMetadataRoundTripWithNewFields() throws {
        let run = AgentRun(
            id: "run-1",
            sessionID: "s1",
            runtime: .claudeCode,
            status: .completed,
            input: "Fix the bug",
            tracePath: "/tmp/trace.jsonl",
            resultSummary: "Done",
            errorSummary: nil,
            provider: "Claude Code",
            model: "claude-sonnet-4-20250514",
            filesChangedCount: 3,
            toolCallCount: 7,
            approvalCount: 2
        )

        try repo.createRun(run, in: "s1")

        let loaded = try repo.getRun(runID: "run-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.provider, "Claude Code")
        XCTAssertEqual(loaded?.model, "claude-sonnet-4-20250514")
        XCTAssertEqual(loaded?.filesChangedCount, 3)
        XCTAssertEqual(loaded?.toolCallCount, 7)
        XCTAssertEqual(loaded?.approvalCount, 2)
    }

    // MARK: - Interrupted Run Detection

    func testInterruptedRunPersists() throws {
        var run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex, input: "task")
        try repo.createRun(run, in: "s1")

        run.markInterrupted()
        try repo.updateRun(run)

        let loaded = try repo.getRun(runID: "run-1")
        XCTAssertEqual(loaded?.status, .interrupted)
        XCTAssertNotNil(loaded?.finishedAt)
    }

    func testIncompleteMetadataDetectedAsInterrupted() throws {
        // Simulate a run that was created but never finished (no finishedAt)
        let run = AgentRun(
            id: "run-1",
            sessionID: "s1",
            runtime: .codex,
            status: .running,
            input: "task"
        )
        try repo.createRun(run, in: "s1")

        let loaded = try repo.getRun(runID: "run-1")
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.status, .running)
        XCTAssertNil(loaded?.finishedAt) // never finished — detectable as interrupted
    }

    // MARK: - Error Summary

    func testErrorSummarySeparateFromResultSummary() throws {
        var run = AgentRun(id: "run-1", sessionID: "s1", runtime: .codex)
        try repo.createRun(run, in: "s1")

        run.start()
        run.fail(error: "Connection timeout")
        try repo.updateRun(run)

        let loaded = try repo.getRun(runID: "run-1")
        XCTAssertEqual(loaded?.errorSummary, "Connection timeout")
        XCTAssertEqual(loaded?.resultSummary, "Connection timeout") // backward compat
    }
}

// MARK: - RunStatus Interrupted Tests

final class RunStatusInterruptedTests: XCTestCase {

    func testInterruptedRawValue() {
        XCTAssertEqual(RunStatus.interrupted.rawValue, "interrupted")
        XCTAssertEqual(RunStatus(rawValue: "interrupted"), .interrupted)
    }

    func testInterruptedIsTerminal() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        run.start()
        XCTAssertTrue(run.markInterrupted())
        XCTAssertTrue(run.isTerminal)
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNotNil(run.finishedAt)
    }

    func testCannotMarkInterruptedFromTerminalState() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        run.start()
        run.complete()
        XCTAssertFalse(run.markInterrupted())
        XCTAssertEqual(run.status, .completed)
    }

    func testMarkInterruptedFromCreated() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        XCTAssertTrue(run.markInterrupted())
        XCTAssertEqual(run.status, .interrupted)
    }

    func testMarkInterruptedFromWaitingApproval() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        run.start()
        run.waitForApproval()
        XCTAssertTrue(run.markInterrupted())
        XCTAssertEqual(run.status, .interrupted)
    }

    // MARK: - New Fields

    func testNewFieldsDefaultValues() {
        let run = AgentRun(sessionID: "s1", runtime: .codex)

        XCTAssertNil(run.provider)
        XCTAssertNil(run.model)
        XCTAssertNil(run.errorSummary)
        XCTAssertEqual(run.filesChangedCount, 0)
        XCTAssertEqual(run.toolCallCount, 0)
        XCTAssertEqual(run.approvalCount, 0)
    }

    func testNewFieldsCodable() throws {
        let run = AgentRun(
            id: "run-1",
            sessionID: "s1",
            runtime: .codex,
            status: .completed,
            provider: "OpenAI",
            model: "gpt-4o",
            filesChangedCount: 5,
            toolCallCount: 12,
            approvalCount: 3
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(run)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AgentRun.self, from: data)

        XCTAssertEqual(decoded.provider, "OpenAI")
        XCTAssertEqual(decoded.model, "gpt-4o")
        XCTAssertEqual(decoded.filesChangedCount, 5)
        XCTAssertEqual(decoded.toolCallCount, 12)
        XCTAssertEqual(decoded.approvalCount, 3)
    }

    func testNewFieldsEquatable() {
        let date = Date()
        let run1 = AgentRun(
            id: "run-1", sessionID: "s1", runtime: .codex, createdAt: date,
            provider: "OpenAI", model: "gpt-4o",
            filesChangedCount: 3, toolCallCount: 5, approvalCount: 1
        )
        let run2 = AgentRun(
            id: "run-1", sessionID: "s1", runtime: .codex, createdAt: date,
            provider: "OpenAI", model: "gpt-4o",
            filesChangedCount: 3, toolCallCount: 5, approvalCount: 1
        )
        let run3 = AgentRun(
            id: "run-1", sessionID: "s1", runtime: .codex, createdAt: date,
            provider: "OpenAI", model: "gpt-4o",
            filesChangedCount: 4, toolCallCount: 5, approvalCount: 1
        )

        XCTAssertEqual(run1, run2)
        XCTAssertNotEqual(run1, run3)
    }
}

// MARK: - Helpers

private func makeEvent(
    type: RuntimeEventType,
    payload: RuntimeEventPayload,
    runID: String? = "run-1"
) -> RuntimeEvent {
    RuntimeEvent(
        runID: runID,
        runtime: .codex,
        type: type,
        payload: payload
    )
}
