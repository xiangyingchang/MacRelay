import XCTest
@testable import AgentClientCore

final class SessionStateReducerActionsTests: XCTestCase {
    private let reducer = SessionStateReducer()

    // MARK: - Response events → no actions

    func test_response_returnsNoActions() {
        let events: [CodexAppServerEvent] = [
            .response(id: 1, result: ["ok": "yep"], error: nil),
            .response(id: 2, result: nil, error: ["message": "fail"]),
            .stderr("some error output"),
            .raw("unparseable line"),
        ]
        for event in events {
            let actions = reducer.actions(from: event)
            XCTAssertTrue(actions.isEmpty, "\(event) should produce no actions")
        }
    }

    // MARK: - Server request events

    func test_serverRequest_withApprovalParams_producesApprovalRequested() {
        let params: [String: Any] = [
            "command": "rm -rf /",
            "reason": "Dangerous operation"
        ]
        let event = CodexAppServerEvent.serverRequest(id: 42, method: "tool/requestApproval", params: params)
        let actions = reducer.actions(from: event)

        XCTAssertEqual(actions.count, 1)
        guard case .approvalRequested = actions[0] else {
            XCTFail("Expected approvalRequested, got \(actions[0])")
            return
        }
    }

    func test_serverRequest_withoutApprovalParams_returnsNoActions() {
        let event = CodexAppServerEvent.serverRequest(
            id: 10, method: "someOtherMethod", params: ["foo": "bar"]
        )
        let actions = reducer.actions(from: event)
        XCTAssertTrue(actions.isEmpty)
    }

    func test_serverRequest_withNilParams_returnsNoActions() {
        // Method must NOT contain "requestApproval" — that is the only gate.
        let event = CodexAppServerEvent.serverRequest(id: 10, method: "some/other/method", params: nil)
        let actions = reducer.actions(from: event)
        XCTAssertTrue(actions.isEmpty)
    }

    // MARK: - Notification events

    func test_notification_threadStarted_producesThreadStarted() {
        let params = ["id": "th_1", "cwd": "/tmp"]
        let event = CodexAppServerEvent.notification(method: "thread/started", params: params)
        let actions = reducer.actions(from: event)

        XCTAssertEqual(actions.count, 1)
        guard case .threadStarted = actions[0] else {
            XCTFail("Expected threadStarted, got \(actions[0])")
            return
        }
    }

    func test_notification_threadStatusChanged_producesStatusChanged() {
        let params = ["status": ["type": "active"]]
        let event = CodexAppServerEvent.notification(method: "thread/status/changed", params: params)
        let actions = reducer.actions(from: event)

        XCTAssertEqual(actions.count, 1)
        guard case .statusChanged = actions[0] else {
            XCTFail("Expected statusChanged, got \(actions[0])")
            return
        }
    }

    func test_notification_settingsUpdated_producesSettingsUpdated() {
        let params = ["threadSettings": ["model": "gpt-4"]]
        let event = CodexAppServerEvent.notification(method: "thread/settings/updated", params: params)
        let actions = reducer.actions(from: event)

        XCTAssertEqual(actions.count, 1)
        guard case .settingsUpdated = actions[0] else {
            XCTFail("Expected settingsUpdated, got \(actions[0])")
            return
        }
    }

    func test_notification_turnStarted_producesTurnStarted() {
        let params = ["turn": ["id": "turn_1"]]
        let event = CodexAppServerEvent.notification(method: "turn/started", params: params)
        let actions = reducer.actions(from: event)

        XCTAssertEqual(actions.count, 1)
        guard case .turnStarted = actions[0] else {
            XCTFail("Expected turnStarted, got \(actions[0])")
            return
        }
    }

    func test_notification_assistantDelta_producesDelta() {
        let params = ["delta": "Hello world"]
        let event = CodexAppServerEvent.notification(method: "item/agentMessage/delta", params: params)
        let actions = reducer.actions(from: event)

        XCTAssertEqual(actions.count, 1)
        guard case let .assistantDelta(text) = actions[0] else {
            XCTFail("Expected assistantDelta, got \(actions[0])")
            return
        }
        XCTAssertEqual(text, "Hello world")
    }

    func test_notification_turnCompleted_producesTurnCompleted() {
        let event = CodexAppServerEvent.notification(method: "turn/completed", params: [:])
        let actions = reducer.actions(from: event)

        XCTAssertEqual(actions.count, 1)
        guard case .turnCompleted = actions[0] else {
            XCTFail("Expected turnCompleted, got \(actions[0])")
            return
        }
    }

    func test_notification_accountRateLimitsUpdated_producesRateLimitsUpdated() {
        let params = ["rateLimits": ["planType": "pro"]]
        let event = CodexAppServerEvent.notification(method: "account/rateLimits/updated", params: params)
        let actions = reducer.actions(from: event)

        XCTAssertEqual(actions.count, 1)
        guard case .rateLimitsUpdated = actions[0] else {
            XCTFail("Expected rateLimitsUpdated, got \(actions[0])")
            return
        }
    }

    func test_notification_error_producesError() {
        let params = ["error": ["message": "Something broke"]]
        let event = CodexAppServerEvent.notification(method: "error", params: params)
        let actions = reducer.actions(from: event)

        XCTAssertEqual(actions.count, 1)
        guard case .error = actions[0] else {
            XCTFail("Expected error action, got \(actions[0])")
            return
        }
    }

    func test_notification_unknownMethod_returnsNoActions() {
        let event = CodexAppServerEvent.notification(method: "some/unknown/method", params: [:])
        let actions = reducer.actions(from: event)
        XCTAssertTrue(actions.isEmpty)
    }

    func test_notification_nilParams_forKnownMethod() {
        let event = CodexAppServerEvent.notification(method: "thread/started", params: nil)
        let actions = reducer.actions(from: event)
        XCTAssertTrue(actions.isEmpty, "notification with nil params should produce no actions")
    }

    // MARK: - Exit event

    #if os(macOS)
    func test_exit_producesExited() {
        let event = CodexAppServerEvent.exit(code: 0, reason: .exit)
        let actions = reducer.actions(from: event)

        XCTAssertEqual(actions.count, 1)
        guard case let .exited(code) = actions[0] else {
            XCTFail("Expected exited, got \(actions[0])")
            return
        }
        XCTAssertEqual(code, 0)
    }

    func test_exit_nonZeroCode_producesExitedWithCode() {
        let event = CodexAppServerEvent.exit(code: 1, reason: .uncaughtSignal)
        let actions = reducer.actions(from: event)

        XCTAssertEqual(actions.count, 1)
        guard case let .exited(code) = actions[0] else {
            XCTFail("Expected exited, got \(actions[0])")
            return
        }
        XCTAssertEqual(code, 1)
    }
    #endif
}
