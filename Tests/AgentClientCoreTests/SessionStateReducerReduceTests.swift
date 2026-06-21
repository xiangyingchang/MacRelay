import XCTest
@testable import AgentClientCore

final class SessionStateReducerReduceTests: XCTestCase {
    private let reducer = SessionStateReducer()

    // MARK: - threadStarted

    func test_threadStarted_setsThreadIDAndCWD() {
        var state = SessionSnapshot()
        let params: [String: Any] = [
            "id": "th_abc123",
            "cwd": "/tmp/project"
        ]
        reducer.reduce(&state, action: .threadStarted(params: params))

        XCTAssertEqual(state.threadID, "th_abc123")
        XCTAssertEqual(state.cwd, "/tmp/project")
    }

    func test_threadStarted_withNestedThreadDict() {
        var state = SessionSnapshot()
        let params: [String: Any] = [
            "thread": [
                "id": "th_nested",
                "cwd": "/nested/path"
            ] as [String: Any]
        ]
        reducer.reduce(&state, action: .threadStarted(params: params))

        XCTAssertEqual(state.threadID, "th_nested")
        XCTAssertEqual(state.cwd, "/nested/path")
    }

    func test_threadStarted_setsStatusFromThreadStatus() {
        var state = SessionSnapshot()
        let params: [String: Any] = [
            "thread": [
                "status": ["type": "active"]
            ] as [String: Any]
        ]
        reducer.reduce(&state, action: .threadStarted(params: params))

        XCTAssertEqual(state.status, .active)
    }

    // MARK: - statusChanged

    func test_statusChanged_updatesStatus() {
        var state = SessionSnapshot()
        let params: [String: Any] = [
            "status": ["type": "completed"]
        ]
        reducer.reduce(&state, action: .statusChanged(params: params))

        XCTAssertEqual(state.status, .completed)
    }

    func test_statusChanged_withWaitingOnApprovalFlag() {
        var state = SessionSnapshot()
        let params: [String: Any] = [
            "status": [
                "type": "active",
                "activeFlags": ["waitingOnApproval"]
            ] as [String: Any]
        ]
        reducer.reduce(&state, action: .statusChanged(params: params))

        XCTAssertEqual(state.status, .waitingOnApproval)
    }

    // MARK: - settingsUpdated

    func test_settingsUpdated_updatesSettings() {
        var state = SessionSnapshot()
        let params: [String: Any] = [
            "threadSettings": [
                "model": "gpt-4",
                "effort": "high",
                "approvalPolicy": "never",
                "sandboxPolicy": ["type": "danger-full-access"] as [String: Any],
                "cwd": "/workspace"
            ] as [String: Any]
        ]
        reducer.reduce(&state, action: .settingsUpdated(params: params))

        XCTAssertEqual(state.settings?.model, "gpt-4")
        XCTAssertEqual(state.settings?.effort, "high")
        XCTAssertEqual(state.settings?.approvalPolicy, "never")
        XCTAssertEqual(state.settings?.sandboxType, "danger-full-access")
        XCTAssertEqual(state.settings?.cwd, "/workspace")
    }

    // MARK: - turnStarted

    func test_turnStarted_createsActiveTurn() {
        var state = SessionSnapshot()
        let params: [String: Any] = [
            "turn": ["id": "turn_xyz"]
        ]
        reducer.reduce(&state, action: .turnStarted(params: params))

        XCTAssertEqual(state.activeTurn?.id, "turn_xyz")
        XCTAssertEqual(state.activeTurn?.assistantText, "")
        XCTAssertFalse(state.activeTurn?.isCompleted ?? true)
        XCTAssertEqual(state.status, .active)
    }

    // MARK: - assistantDelta

    func test_assistantDelta_appendsText() {
        var state = SessionSnapshot()
        state.activeTurn = TurnSnapshot(id: "turn_1")

        reducer.reduce(&state, action: .assistantDelta("Hello "))
        reducer.reduce(&state, action: .assistantDelta("world"))

        XCTAssertEqual(state.activeTurn?.assistantText, "Hello world")
    }

    func test_assistantDelta_withoutActiveTurn_createsOne() {
        var state = SessionSnapshot()
        XCTAssertNil(state.activeTurn)

        reducer.reduce(&state, action: .assistantDelta("Spontaneous delta"))
        XCTAssertEqual(state.activeTurn?.assistantText, "Spontaneous delta")
    }

    // MARK: - turnCompleted

    func test_turnCompleted_marksTurnAndSetsStatus() {
        var state = SessionSnapshot()
        state.activeTurn = TurnSnapshot(id: "turn_1")

        reducer.reduce(&state, action: .turnCompleted(params: [:]))

        XCTAssertEqual(state.activeTurn?.isCompleted, true)
        XCTAssertEqual(state.status, .completed)
    }

    func test_turnCompleted_withPriorError_marksFailed() {
        var state = SessionSnapshot()
        state.activeTurn = TurnSnapshot(id: "turn_1")
        state.lastError = SessionErrorSnapshot(message: "Boom", code: nil, willRetry: false)

        reducer.reduce(&state, action: .turnCompleted(params: [:]))

        XCTAssertEqual(state.activeTurn?.isCompleted, true)
        XCTAssertEqual(state.status, .failed)
    }

    // MARK: - approvalRequested

    func test_approvalRequested_addsPendingApproval() {
        var state = SessionSnapshot()
        guard let approval = CodexApprovalRequest(
            requestID: 101,
            method: "tool/requestApproval",
            params: ["command": "ls -la", "reason": "List files"]
        ) else {
            XCTFail("Could not create CodexApprovalRequest")
            return
        }
        reducer.reduce(&state, action: .approvalRequested(approval))

        let pending = state.pendingApprovals["101"]
        XCTAssertNotNil(pending)
        XCTAssertEqual(pending?.requestID, 101)
        XCTAssertEqual(pending?.method, "tool/requestApproval")
        XCTAssertEqual(pending?.command, "ls -la")
        XCTAssertEqual(pending?.reason, "List files")
        XCTAssertTrue(pending?.isPending ?? false)
        XCTAssertEqual(state.status, .waitingOnApproval)
    }

    func test_approvalRequested_withoutRequestApprovalMethod_isIgnored() {
        // The reducer only creates approvals via .approvalRequested action,
        // but the action enum itself has no filtering — filtering happens
        // in SessionStateReducer.actions(from:) by CodexApprovalRequest's
        // failable init. This test confirms that the failable init rejects
        // non-requestApproval methods.
        let request = CodexApprovalRequest(
            requestID: 101,
            method: "command/run",
            params: ["command": "ls -la"]
        )
        XCTAssertNil(request)
    }

    // MARK: - approvalResolved

    func test_approvalResolved_updatesDecision() {
        var state = SessionSnapshot()
        guard let approval = CodexApprovalRequest(
            requestID: 101,
            method: "tool/requestApproval",
            params: [:]
        ) else {
            XCTFail("Could not create CodexApprovalRequest")
            return
        }
        reducer.reduce(&state, action: .approvalRequested(approval))

        reducer.reduce(&state, action: .approvalResolved(requestID: 101, decision: "accept"))

        let resolved = state.pendingApprovals["101"]
        XCTAssertEqual(resolved?.decision, "accept")
        XCTAssertFalse(resolved?.isPending ?? true)
    }

    func test_approvalResolved_unknownRequestID_doesNothing() {
        var state = SessionSnapshot()
        state.status = .waitingOnApproval

        reducer.reduce(&state, action: .approvalResolved(requestID: 999, decision: "reject"))

        XCTAssertTrue(state.pendingApprovals.isEmpty)
        XCTAssertEqual(state.status, .waitingOnApproval)
    }

    // MARK: - diffUpdated

    func test_diffUpdated_setsTurnDiff() {
        var state = SessionSnapshot()
        guard let diff = CodexTurnDiffUpdated(
            method: "turn/diff/updated",
            params: [
                "threadId": "th_1",
                "turnId": "turn_1",
                "diff": """
                diff --git a/a.swift b/a.swift
                --- a/a.swift
                +++ b/a.swift
                @@ -1 +1 @@
                -old
                +new
                diff --git a/b.swift b/b.swift
                --- a/b.swift
                +++ b/b.swift
                @@ -1 +1 @@
                -old
                +new
                """
            ]
        ) else {
            XCTFail("Could not create CodexTurnDiffUpdated")
            return
        }
        reducer.reduce(&state, action: .diffUpdated(diff))

        XCTAssertNotNil(state.turnDiff)
        XCTAssertEqual(state.turnDiff?.changedFiles, ["a.swift", "b.swift"])
    }

    // MARK: - fileChangeUpdated

    func test_fileChangeUpdated_addsChange() {
        var state = SessionSnapshot()
        guard let change = CodexFileChangeUpdated(
            method: "item/started",
            params: [
                "threadId": "th_1",
                "turnId": "turn_1",
                "item": [
                    "id": "fc_1",
                    "type": "fileChange",
                    "path": "Sources/main.swift",
                    "changeKind": "modified",
                    "diff": "+1 -1"
                ] as [String: Any]
            ]
        ) else {
            XCTFail("Could not create CodexFileChangeUpdated")
            return
        }
        reducer.reduce(&state, action: .fileChangeUpdated(change))

        XCTAssertEqual(state.fileChanges.count, 1)
        let entry = state.fileChanges.first?.value
        XCTAssertEqual(entry?.path, "Sources/main.swift")
        XCTAssertEqual(entry?.changeKind, "modified")
    }

    // MARK: - error

    func test_error_setsLastError() {
        var state = SessionSnapshot()
        let params: [String: Any] = [
            "error": [
                "message": "Rate limit exceeded",
                "codexErrorInfo": "rate_limited"
            ] as [String: Any]
        ]
        reducer.reduce(&state, action: .error(params: params))

        XCTAssertEqual(state.lastError?.message, "Rate limit exceeded")
        XCTAssertEqual(state.lastError?.code, "rate_limited")
        XCTAssertEqual(state.status, .systemError)
    }

    func test_error_withMinimalParams() {
        var state = SessionSnapshot()
        reducer.reduce(&state, action: .error(params: [:]))

        XCTAssertEqual(state.lastError?.message, "Unknown error")
        XCTAssertNil(state.lastError?.code)
        XCTAssertEqual(state.status, .systemError)
    }

    // MARK: - rateLimitsUpdated

    func test_rateLimitsUpdated_setsSnapshot() {
        var state = SessionSnapshot()
        let params: [String: Any] = [
            "rateLimits": [
                "planType": "pro",
                "limitId": "api_limit",
                "rateLimitReachedType": "soft"
            ] as [String: Any]
        ]
        reducer.reduce(&state, action: .rateLimitsUpdated(params: params))

        XCTAssertEqual(state.rateLimit?.planType, "pro")
        XCTAssertEqual(state.rateLimit?.limitID, "api_limit")
        XCTAssertEqual(state.rateLimit?.rateLimitReachedType, "soft")
    }

    // MARK: - exited

    func test_exited_setsFlags() {
        var state = SessionSnapshot()
        state.status = .active

        reducer.reduce(&state, action: .exited(code: 1))

        XCTAssertTrue(state.hasExited)
        XCTAssertEqual(state.status, .exited)
    }
}
