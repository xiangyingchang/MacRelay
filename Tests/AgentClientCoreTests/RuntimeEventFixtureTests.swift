import XCTest
@testable import AgentClientCore

/// Tests for RuntimeEvent fixtures and the reducer pipeline.
///
/// These tests verify that:
/// 1. Fixtures can be loaded and decoded correctly
/// 2. The reducer produces correct snapshots from event sequences
/// 3. The fixtures represent realistic Agent Harness scenarios
///
/// Fixtures are reusable: TraceReader, TimelineBuilder, and Replay can
/// all use the same fixtures for their own tests.
final class RuntimeEventFixtureTests: XCTestCase {

    // MARK: - Fixture Loading Tests

    /// Test that all fixture files can be loaded without errors.
    func testLoadAllFixtures() throws {
        let fixtureNames = ["normal_coding_run", "approval_rejected", "tool_failed"]

        for name in fixtureNames {
            let events = try FixtureLoader.loadFixture(name)
            XCTAssertFalse(events.isEmpty, "Fixture '\(name)' should not be empty")
            print("[\(name)] Loaded \(events.count) events")
        }
    }

    /// Test that fixture events have valid structure.
    func testFixtureEventStructure() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")

        for event in events {
            // Every event must have an ID
            XCTAssertFalse(event.id.isEmpty, "Event should have non-empty ID")

            // Every event must have a valid version
            XCTAssertGreaterThanOrEqual(event.version, 1, "Event version should be >= 1")

            // Every event must have a timestamp
            XCTAssertNotNil(event.timestamp, "Event should have a timestamp")

            // Every event must have a session ID (for these fixtures)
            XCTAssertNotNil(event.sessionID, "Fixture event should have sessionID")

            // Every event must have a runtime
            XCTAssertNotNil(event.runtime, "Event should have a runtime identifier")
        }
    }

    // MARK: - Scenario A: Normal Coding Run

    /// Test a complete coding session: user input → tool call → approval → file change → completion.
    ///
    /// Expected flow:
    /// 1. Session starts
    /// 2. User sends input
    /// 3. Agent reads file
    /// 4. Agent requests approval for write
    /// 5. User approves
    /// 6. File is modified
    /// 7. Agent runs tests (with approval)
    /// 8. Tests pass
    /// 9. Turn completes
    ///
    /// Verification:
    /// - snapshot.status == .completed
    /// - fileChanges contains LoginView.swift
    /// - events count == 15
    func testNormalCodingRun() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")
        let snapshot = FixtureLoader.reduceToSnapshot(events)

        // Verify event count
        XCTAssertEqual(events.count, 15, "Normal coding run should have 15 events")

        // Verify final status
        XCTAssertEqual(snapshot.status, .completed, "Final status should be completed")

        // Verify session was started
        XCTAssertEqual(snapshot.threadID, "session-001", "Thread ID should be set")

        // Verify file changes
        XCTAssertFalse(snapshot.fileChanges.isEmpty, "Should have file changes")
        let changedFiles = Array(snapshot.fileChanges.values)
        XCTAssertTrue(
            changedFiles.contains { $0.path?.contains("LoginView.swift") ?? false },
            "LoginView.swift should be in file changes"
        )

        // Verify turn was completed
        XCTAssertFalse(snapshot.completedTurns.isEmpty, "Should have completed turns")
        let lastTurn = snapshot.completedTurns.last
        XCTAssertEqual(lastTurn?.id, "turn-001", "Last turn should be turn-001")
        XCTAssertTrue(lastTurn?.isCompleted ?? false, "Turn should be marked as completed")

        // Verify no errors
        XCTAssertNil(snapshot.lastError, "Should have no errors")

        // Verify user message was captured
        XCTAssertEqual(
            lastTurn?.userMessage,
            "修复登录页面的崩溃问题",
            "User message should be captured"
        )

        // Verify assistant response
        XCTAssertTrue(
            lastTurn?.assistantText.contains("修复完成") ?? false,
            "Assistant should report completion"
        )
    }

    // MARK: - Scenario B: Approval Rejected

    /// Test an approval rejection scenario.
    ///
    /// Expected flow:
    /// 1. Session starts
    /// 2. User sends input
    /// 3. Agent requests risky operation (rm -rf)
    /// 4. User rejects
    /// 5. Turn errors
    /// 6. Session stops
    ///
    /// Verification:
    /// - snapshot.status reflects rejection
    /// - approval state shows rejection
    /// - turn error message is present
    func testApprovalRejected() throws {
        let events = try FixtureLoader.loadFixture("approval_rejected")
        let snapshot = FixtureLoader.reduceToSnapshot(events)

        // Verify event count
        XCTAssertEqual(events.count, 7, "Approval rejected should have 7 events")

        // Verify session was started
        XCTAssertEqual(snapshot.threadID, "session-002", "Thread ID should be set")

        // Verify approval was requested and resolved
        // The approval should still be in pendingApprovals but with decision set
        let approval = snapshot.pendingApprovals.values.first
        XCTAssertNotNil(approval, "Should have an approval")
        XCTAssertEqual(approval?.method, "requestApproval_run_shell_command", "Approval tool should be requestApproval_run_shell_command")
        XCTAssertEqual(approval?.decision, "reject", "Approval should be rejected")
        XCTAssertFalse(approval?.isPending ?? true, "Approval should not be pending after rejection")

        // Verify turn error
        XCTAssertNotNil(snapshot.lastError, "Should have an error")
        XCTAssertTrue(
            snapshot.lastError?.message.contains("用户拒绝") ?? false,
            "Error should mention user rejection"
        )
    }

    // MARK: - Scenario C: Tool Failed

    /// Test a tool failure scenario.
    ///
    /// Expected flow:
    /// 1. Session starts
    /// 2. User sends input
    /// 3. Agent requests tool call
    /// 4. Tool fails
    /// 5. Error is recorded
    /// 6. Turn completes (with error)
    ///
    /// Verification:
    /// - error state is present
    /// - tool failure is recorded
    /// - turn completes despite error
    func testToolFailed() throws {
        let events = try FixtureLoader.loadFixture("tool_failed")
        let snapshot = FixtureLoader.reduceToSnapshot(events)

        // Verify event count
        XCTAssertEqual(events.count, 7, "Tool failed should have 7 events")

        // Verify session was started
        XCTAssertEqual(snapshot.threadID, "session-003", "Thread ID should be set")

        // Verify error is present
        XCTAssertNotNil(snapshot.lastError, "Should have an error")
        XCTAssertTrue(
            snapshot.lastError?.message.contains("Test target failed") ?? false,
            "Error should mention test failure"
        )
        XCTAssertEqual(snapshot.lastError?.code, "TEST_FAILURE", "Error code should be TEST_FAILURE")

        // Verify turn completed (even with error)
        XCTAssertFalse(snapshot.completedTurns.isEmpty, "Should have completed turns")
        let lastTurn = snapshot.completedTurns.last
        XCTAssertEqual(lastTurn?.id, "turn-003", "Last turn should be turn-003")

        // Verify user message
        XCTAssertEqual(
            lastTurn?.userMessage,
            "运行测试套件",
            "User message should be captured"
        )
    }

    // MARK: - Snapshot Rebuild Test

    /// Test that fixtures can be used to rebuild snapshots.
    /// This is the core of the Trace → Snapshot pipeline.
    func testSnapshotRebuild() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")

        // Reduce to snapshot
        let snapshot = FixtureLoader.reduceToSnapshot(events)

        // Verify basic snapshot properties
        XCTAssertNotNil(snapshot.threadID, "Snapshot should have threadID")
        // Settings are nil because the fixture doesn't have a settings.updated event
        XCTAssertNil(snapshot.settings, "Settings should be nil for this fixture")
        XCTAssertFalse(snapshot.completedTurns.isEmpty, "Snapshot should have completed turns")

        // Verify snapshot can answer: "what happened?"
        let fileChangeCount = snapshot.fileChanges.count
        XCTAssertGreaterThan(fileChangeCount, 0, "Should have at least one file change")

        // Verify approvals are resolved (isPending should be false)
        let approvalCount = snapshot.pendingApprovals.values.filter { $0.isPending }.count
        XCTAssertEqual(approvalCount, 0, "All approvals should be resolved")
    }

    // MARK: - Fixture Reusability

    /// Test that fixtures can be used by multiple consumers.
    /// This verifies the fixture format is generic enough for:
    /// - TraceReader
    /// - TimelineBuilder
    /// - Replay
    func testFixtureReusability() throws {
        let events = try FixtureLoader.loadFixture("normal_coding_run")

        // TraceReader use case: extract turn boundaries
        let turnStarts = events.filter { $0.type == .turnStarted }
        let turnEnds = events.filter { $0.type == .turnCompleted }
        XCTAssertEqual(turnStarts.count, turnEnds.count, "Turn starts and ends should match")

        // TimelineBuilder use case: extract tool calls
        let toolCalls = events.filter {
            $0.type == .toolCallRequested ||
            $0.type == .fileChangeDetected
        }
        XCTAssertGreaterThan(toolCalls.count, 0, "Should have tool calls for timeline")

        // Replay use case: events have sequence
        for i in 1..<events.count {
            XCTAssertTrue(
                events[i].timestamp >= events[i-1].timestamp,
                "Events should be in chronological order"
            )
        }
    }
}
