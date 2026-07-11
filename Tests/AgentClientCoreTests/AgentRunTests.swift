import XCTest
@testable import AgentClientCore

final class AgentRunTests: XCTestCase {
    // MARK: - RunStatus Tests

    func testRunStatusRawValues() {
        XCTAssertEqual(RunStatus.created.rawValue, "created")
        XCTAssertEqual(RunStatus.running.rawValue, "running")
        XCTAssertEqual(RunStatus.waitingApproval.rawValue, "waitingApproval")
        XCTAssertEqual(RunStatus.completed.rawValue, "completed")
        XCTAssertEqual(RunStatus.failed.rawValue, "failed")
        XCTAssertEqual(RunStatus.cancelled.rawValue, "cancelled")
    }

    func testRunStatusFromRawValue() {
        XCTAssertEqual(RunStatus(rawValue: "created"), .created)
        XCTAssertEqual(RunStatus(rawValue: "running"), .running)
        XCTAssertEqual(RunStatus(rawValue: "waitingApproval"), .waitingApproval)
        XCTAssertEqual(RunStatus(rawValue: "completed"), .completed)
        XCTAssertEqual(RunStatus(rawValue: "failed"), .failed)
        XCTAssertEqual(RunStatus(rawValue: "cancelled"), .cancelled)
        XCTAssertNil(RunStatus(rawValue: "invalid"))
    }

    // MARK: - AgentRun Init Tests

    func testAgentRunInit() {
        let id = UUID().uuidString
        let sessionID = "session-123"
        let runtime = RuntimeIdentifier.codex
        let input = "Fix the bug"
        let tracePath = "/tmp/trace.log"

        let run = AgentRun(
            id: id,
            sessionID: sessionID,
            runtime: runtime,
            input: input,
            tracePath: tracePath
        )

        XCTAssertEqual(run.id, id)
        XCTAssertEqual(run.sessionID, sessionID)
        XCTAssertEqual(run.runtime, runtime)
        XCTAssertEqual(run.status, .created)
        XCTAssertEqual(run.input, input)
        XCTAssertEqual(run.tracePath, tracePath)
        XCTAssertNotNil(run.createdAt)
        XCTAssertNil(run.startedAt)
        XCTAssertNil(run.finishedAt)
        XCTAssertNil(run.resultSummary)
        XCTAssertTrue(run.isTerminal == false)
        XCTAssertNil(run.duration)
        XCTAssertNil(run.totalDuration)
    }

    func testAgentRunDefaultInit() {
        let run = AgentRun(
            sessionID: "session-1",
            runtime: .claudeCode
        )

        XCTAssertFalse(run.id.isEmpty)
        XCTAssertEqual(run.sessionID, "session-1")
        XCTAssertEqual(run.runtime, .claudeCode)
        XCTAssertEqual(run.status, .created)
        XCTAssertNil(run.input)
        XCTAssertNil(run.tracePath)
        XCTAssertNil(run.startedAt)
    }

    // MARK: - State Transition Tests

    func testRunLifecycleHappyPath() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)

        // created → running
        XCTAssertTrue(run.start())
        XCTAssertEqual(run.status, .running)
        XCTAssertNotNil(run.startedAt)

        // running → waitingApproval
        XCTAssertTrue(run.waitForApproval())
        XCTAssertEqual(run.status, .waitingApproval)

        // waitingApproval → running
        XCTAssertTrue(run.resume())
        XCTAssertEqual(run.status, .running)

        // running → completed
        XCTAssertTrue(run.complete(summary: "Success"))
        XCTAssertEqual(run.status, .completed)
        XCTAssertNotNil(run.finishedAt)
        XCTAssertEqual(run.resultSummary, "Success")
        XCTAssertTrue(run.isTerminal)
        XCTAssertNotNil(run.duration)
    }

    func testRunLifecycleFailedPath() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)

        // created → running
        XCTAssertTrue(run.start())
        XCTAssertEqual(run.status, .running)

        // running → failed
        XCTAssertTrue(run.fail(error: "API error"))
        XCTAssertEqual(run.status, .failed)
        XCTAssertNotNil(run.finishedAt)
        XCTAssertEqual(run.resultSummary, "API error")
        XCTAssertTrue(run.isTerminal)
    }

    func testRunLifecycleCancelledPath() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)

        // created → cancelled
        XCTAssertTrue(run.cancel())
        XCTAssertEqual(run.status, .cancelled)
        XCTAssertNotNil(run.finishedAt)
        XCTAssertTrue(run.isTerminal)
    }

    func testRunLifecycleCancelledFromRunning() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)

        XCTAssertTrue(run.start())
        XCTAssertTrue(run.cancel())
        XCTAssertEqual(run.status, .cancelled)
    }

    func testRunLifecycleCancelledFromWaitingApproval() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)

        XCTAssertTrue(run.start())
        XCTAssertTrue(run.waitForApproval())
        XCTAssertTrue(run.cancel())
        XCTAssertEqual(run.status, .cancelled)
    }

    // MARK: - Invalid State Transitions

    func testRunCannotStartFromRunning() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        XCTAssertTrue(run.start())
        XCTAssertFalse(run.start()) // Already running
        XCTAssertEqual(run.status, .running)
    }

    func testRunCannotStartFromCompleted() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        XCTAssertTrue(run.start())
        XCTAssertTrue(run.complete())
        XCTAssertFalse(run.start()) // Already completed
        XCTAssertEqual(run.status, .completed)
    }

    func testRunCannotStartFromFailed() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        XCTAssertTrue(run.start())
        XCTAssertTrue(run.fail())
        XCTAssertFalse(run.start()) // Already failed
        XCTAssertEqual(run.status, .failed)
    }

    func testRunCannotStartFromCancelled() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        XCTAssertTrue(run.cancel())
        XCTAssertFalse(run.start()) // Already cancelled
        XCTAssertEqual(run.status, .cancelled)
    }

    func testRunCannotCompleteFromCreated() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        XCTAssertFalse(run.complete()) // Not running
        XCTAssertEqual(run.status, .created)
    }

    func testRunCannotCompleteFromWaitingApproval() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        XCTAssertTrue(run.start())
        XCTAssertTrue(run.waitForApproval())
        XCTAssertFalse(run.complete()) // Not running
        XCTAssertEqual(run.status, .waitingApproval)
    }

    func testRunCannotFailFromCreated() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        XCTAssertFalse(run.fail()) // Not running
        XCTAssertEqual(run.status, .created)
    }

    func testRunCannotWaitForApprovalFromCreated() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        XCTAssertFalse(run.waitForApproval()) // Not running
        XCTAssertEqual(run.status, .created)
    }

    func testRunCannotResumeFromRunning() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        XCTAssertTrue(run.start())
        XCTAssertFalse(run.resume()) // Not waiting approval
        XCTAssertEqual(run.status, .running)
    }

    // MARK: - Duration Tests

    func testRunDurationNilWhenNotFinished() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        run.start()
        XCTAssertNil(run.duration)
    }

    func testRunDurationNilWhenCreated() {
        let run = AgentRun(sessionID: "s1", runtime: .codex)
        XCTAssertNil(run.duration)
        XCTAssertNil(run.startedAt)
    }

    func testRunDurationCalculatedWhenFinished() {
        var run = AgentRun(sessionID: "s1", runtime: .codex)
        run.start()
        // Small delay to ensure duration > 0
        Thread.sleep(forTimeInterval: 0.01)
        run.complete()
        XCTAssertNotNil(run.duration)
        XCTAssertGreaterThan(run.duration!, 0)
    }

    func testRunTotalDurationIncludesCreatedToFinished() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        var run = AgentRun(
            sessionID: "s1",
            runtime: .codex,
            createdAt: createdAt
        )
        // totalDuration is nil before finish
        XCTAssertNil(run.totalDuration)

        run.start()
        run.complete()

        // totalDuration should be > duration (includes created→started gap)
        XCTAssertNotNil(run.totalDuration)
        XCTAssertNotNil(run.duration)
    }

    // MARK: - Equatable Tests

    func testAgentRunEquatable() {
        let date = Date()
        let run1 = AgentRun(id: "id-1", sessionID: "s1", runtime: .codex, createdAt: date)
        let run2 = AgentRun(id: "id-1", sessionID: "s1", runtime: .codex, createdAt: date)
        let run3 = AgentRun(id: "id-2", sessionID: "s1", runtime: .codex, createdAt: date)

        XCTAssertEqual(run1, run2)
        XCTAssertNotEqual(run1, run3)
    }

    // MARK: - Codable Tests

    func testAgentRunCodable() throws {
        let run = AgentRun(
            id: "test-id",
            sessionID: "session-1",
            runtime: .codex,
            status: .completed,
            input: "Fix the bug",
            tracePath: "/tmp/trace.log",
            resultSummary: "Done"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(run)
        XCTAssertFalse(data.isEmpty)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AgentRun.self, from: data)

        XCTAssertEqual(decoded.id, run.id)
        XCTAssertEqual(decoded.sessionID, run.sessionID)
        XCTAssertEqual(decoded.runtime, run.runtime)
        XCTAssertEqual(decoded.status, run.status)
        XCTAssertEqual(decoded.input, run.input)
        XCTAssertEqual(decoded.tracePath, run.tracePath)
        XCTAssertEqual(decoded.resultSummary, run.resultSummary)
    }

    // MARK: - RunMetadata Tests

    func testRunMetadataCodable() throws {
        let run = AgentRun(
            id: "run-1",
            sessionID: "session-1",
            runtime: .codex,
            status: .completed,
            input: "Fix the bug",
            tracePath: "/tmp/trace.log",
            resultSummary: "Done"
        )

        let metadata = RunMetadata(
            run: run,
            sessionID: "session-1",
            tracePath: "/tmp/trace.log",
            tags: ["priority": "high"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RunMetadata.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.run.id, run.id)
        XCTAssertEqual(decoded.sessionID, "session-1")
        XCTAssertEqual(decoded.tags["priority"], "high")
    }

    func testRunMetadataDefaultVersion() {
        let run = AgentRun(sessionID: "s1", runtime: .codex)
        let metadata = RunMetadata(run: run, sessionID: "s1")
        XCTAssertEqual(metadata.version, 1)
        XCTAssertTrue(metadata.tags.isEmpty)
    }
}

// MARK: - SessionSnapshot Run Integration Tests

final class SessionSnapshotRunTests: XCTestCase {
    var reducer: SessionStateReducer!
    var state: SessionSnapshot!

    override func setUp() {
        super.setUp()
        reducer = SessionStateReducer()
        state = SessionSnapshot()
    }

    override func tearDown() {
        reducer = nil
        state = nil
        super.tearDown()
    }

    func testRunStartedCreatesActiveRun() {
        reducer.reduce(&state, action: .runStarted(
            runID: "run-1",
            input: "Test input",
            runtime: .codex
        ))

        XCTAssertNotNil(state.activeRun)
        XCTAssertEqual(state.activeRun?.id, "run-1")
        XCTAssertEqual(state.activeRun?.input, "Test input")
        XCTAssertEqual(state.activeRun?.runtime, .codex)
        XCTAssertEqual(state.activeRun?.status, .running)
    }

    func testRunWaitingApproval() {
        reducer.reduce(&state, action: .runStarted(
            runID: "run-1",
            input: nil,
            runtime: .codex
        ))
        reducer.reduce(&state, action: .runWaitingApproval(runID: "run-1"))

        XCTAssertEqual(state.activeRun?.status, .waitingApproval)
    }

    func testRunResumed() {
        reducer.reduce(&state, action: .runStarted(
            runID: "run-1",
            input: nil,
            runtime: .codex
        ))
        reducer.reduce(&state, action: .runWaitingApproval(runID: "run-1"))
        reducer.reduce(&state, action: .runResumed(runID: "run-1"))

        XCTAssertEqual(state.activeRun?.status, .running)
    }

    func testRunCompletedMovesToCompletedRuns() {
        reducer.reduce(&state, action: .runStarted(
            runID: "run-1",
            input: nil,
            runtime: .codex
        ))
        reducer.reduce(&state, action: .runCompleted(runID: "run-1", summary: "Success"))

        XCTAssertNil(state.activeRun)
        XCTAssertEqual(state.completedRuns.count, 1)
        XCTAssertEqual(state.completedRuns.first?.id, "run-1")
        XCTAssertEqual(state.completedRuns.first?.status, .completed)
        XCTAssertEqual(state.completedRuns.first?.resultSummary, "Success")
    }

    func testRunFailedMovesToCompletedRuns() {
        reducer.reduce(&state, action: .runStarted(
            runID: "run-1",
            input: nil,
            runtime: .codex
        ))
        reducer.reduce(&state, action: .runFailed(runID: "run-1", error: "API error"))

        XCTAssertNil(state.activeRun)
        XCTAssertEqual(state.completedRuns.count, 1)
        XCTAssertEqual(state.completedRuns.first?.id, "run-1")
        XCTAssertEqual(state.completedRuns.first?.status, .failed)
        XCTAssertEqual(state.completedRuns.first?.resultSummary, "API error")
    }

    func testRunCancelledMovesToCompletedRuns() {
        reducer.reduce(&state, action: .runStarted(
            runID: "run-1",
            input: nil,
            runtime: .codex
        ))
        reducer.reduce(&state, action: .runCancelled(runID: "run-1"))

        XCTAssertNil(state.activeRun)
        XCTAssertEqual(state.completedRuns.count, 1)
        XCTAssertEqual(state.completedRuns.first?.id, "run-1")
        XCTAssertEqual(state.completedRuns.first?.status, .cancelled)
    }

    func testRunActionsIgnoredForWrongRunID() {
        reducer.reduce(&state, action: .runStarted(
            runID: "run-1",
            input: nil,
            runtime: .codex
        ))
        reducer.reduce(&state, action: .runCompleted(runID: "run-2", summary: nil))

        // Should not affect active run
        XCTAssertNotNil(state.activeRun)
        XCTAssertEqual(state.activeRun?.id, "run-1")
        XCTAssertEqual(state.completedRuns.count, 0)
    }

    func testMultipleRunsSequence() {
        // First run
        reducer.reduce(&state, action: .runStarted(
            runID: "run-1",
            input: "First task",
            runtime: .codex
        ))
        reducer.reduce(&state, action: .runCompleted(runID: "run-1", summary: "Done"))

        // Second run
        reducer.reduce(&state, action: .runStarted(
            runID: "run-2",
            input: "Second task",
            runtime: .claudeCode
        ))

        XCTAssertEqual(state.completedRuns.count, 1)
        XCTAssertNotNil(state.activeRun)
        XCTAssertEqual(state.activeRun?.id, "run-2")
        XCTAssertEqual(state.activeRun?.runtime, .claudeCode)
    }
}
