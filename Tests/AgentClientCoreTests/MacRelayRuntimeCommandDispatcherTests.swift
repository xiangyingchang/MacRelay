import XCTest
@testable import AgentClientCore

@MainActor
final class MacRelayRuntimeCommandDispatcherTests: XCTestCase {
    private final class RuntimeSpy: AgentRuntime {
        enum Call: Equatable {
            case clear
            case enqueue(String)
        }

        var calls: [Call] = []
        var enqueueError: Error?
        var selectedIDs: [String] = []

        override func clearCurrentThread() {
            calls.append(.clear)
            currentThreadID = nil
        }

        override func enqueueDraft(
            cwd: String,
            text: String,
            model: String?,
            effort: String?,
            threadSandbox: String,
            turnSandbox: String,
            approvalPolicy: String
        ) throws {
            calls.append(.enqueue(text))
            if let enqueueError { throw enqueueError }
        }

        override func selectSession(sessionID: String) throws {
            selectedIDs.append(sessionID)
            selectedSessionID = sessionID
            currentThreadID = sessionID
        }
    }

    private enum TestError: Error { case rejected }

    func test_sessionStartWithoutPromptClearsOldThreadBeforePreparingNewSession() throws {
        let runtime = RuntimeSpy()
        runtime.currentThreadID = "old-thread"
        runtime.selectedSessionID = "old-thread"
        var callbackCalls = 0
        var dispatcher = MacRelayRuntimeCommandDispatcher(runtime: runtime, defaultCWD: { "/tmp" })
        dispatcher.onSessionStart = { callbackCalls += 1 }

        let payload = RelaySessionStartCommandPayload(cwd: "/tmp", planMode: false, permissionMode: "Read Only", initialPrompt: nil)
        _ = try dispatcher.dispatch(commandType: .sessionStart, payloadData: JSONEncoder().encode(payload))

        XCTAssertEqual(runtime.calls, [.clear, .enqueue("")])
        XCTAssertEqual(callbackCalls, 1)
    }

    func test_sessionStartWithPromptCreatesNewThreadInsteadOfAppendingToOldThread() throws {
        let runtime = RuntimeSpy()
        runtime.currentThreadID = "old-thread"
        var callbackCalls = 0
        var dispatcher = MacRelayRuntimeCommandDispatcher(runtime: runtime, defaultCWD: { "/tmp" })
        dispatcher.onSessionStart = { callbackCalls += 1 }

        let payload = RelaySessionStartCommandPayload(cwd: "/tmp", planMode: false, permissionMode: "Read Only", initialPrompt: "first message")
        _ = try dispatcher.dispatch(commandType: .sessionStart, payloadData: JSONEncoder().encode(payload))

        XCTAssertEqual(runtime.calls, [.clear, .enqueue("first message")])
        XCTAssertNil(runtime.currentThreadID)
        XCTAssertEqual(callbackCalls, 1)
    }

    func test_synchronousStartFailureDoesNotEnterPendingNewSessionState() throws {
        let runtime = RuntimeSpy()
        runtime.currentThreadID = "old-thread"
        runtime.enqueueError = TestError.rejected
        var callbackCalls = 0
        var dispatcher = MacRelayRuntimeCommandDispatcher(runtime: runtime, defaultCWD: { "/tmp" })
        dispatcher.onSessionStart = { callbackCalls += 1 }

        let payload = RelaySessionStartCommandPayload(cwd: "/tmp", planMode: false, permissionMode: "Read Only", initialPrompt: nil)
        XCTAssertThrowsError(
            try dispatcher.dispatch(commandType: .sessionStart, payloadData: JSONEncoder().encode(payload))
        )

        XCTAssertEqual(runtime.calls, [.clear, .enqueue("")])
        XCTAssertEqual(callbackCalls, 0)
        XCTAssertEqual(runtime.selectedIDs, ["old-thread"])
        XCTAssertEqual(runtime.currentThreadID, "old-thread")
    }

    func test_runtimeFailureSignalReachesRegisteredLifecycleCallback() {
        let runtime = RuntimeSpy()
        var failures: [String] = []
        runtime.onSessionStartFailed = { failures.append($0) }

        runtime.reportSessionStartFailure("thread start failed")

        XCTAssertEqual(failures, ["thread start failed"])
    }
}
