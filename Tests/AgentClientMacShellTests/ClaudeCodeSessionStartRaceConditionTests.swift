import XCTest
import AgentClientCore
@testable import AgentClientMacShell

// MARK: - Regression tests for consecutive session creation race condition
//
// Root cause: the threadStart response handler guarded on
// `currentThreadID == nil` before accepting the new session ID.
// A delayed thread/started notification from session A would set
// currentThreadID, causing session B's response to be silently
// discarded. iOS would then poll for 30 seconds and time out.
//
// Fix: response handler always accepts; notification handler is
// idempotent (skips if currentThreadID already matches).

@MainActor
final class ClaudeCodeSessionStartRaceConditionTests: XCTestCase {

    // Simulates a thread/start JSON-RPC response from claude-app-server.
    private func threadStartResponse(requestID: Int, threadID: String) -> String {
        """
        {"jsonrpc":"2.0","id":\(requestID),"result":{"thread_id":"\(threadID)"}}
        """
    }

    // Simulates a thread/started JSON-RPC notification from claude-app-server.
    private func threadStartedNotification(threadID: String) -> String {
        """
        {"jsonrpc":"2.0","method":"thread/started","params":{"id":"\(threadID)"}}
        """
    }

    // Helper: set up runtime as if startThread() was called,
    // so the response handler finds the matching pending request.
    private func prepareRuntimeForThreadStart(
        _ runtime: ClaudeCodeRuntime,
        requestID: Int
    ) {
        runtime.registerPendingRequest(id: requestID, kind: .threadStart)
    }

    // MARK: - Test: delayed notification does not discard second response

    func test_delayedNotificationFromFirstSessionDoesNotDiscardSecondResponse() throws {
        let runtime = ClaudeCodeRuntime()
        var threadStartedCalls: [String] = []
        runtime.onThreadStarted = { threadStartedCalls.append($0) }
        runtime.currentThreadID = nil

        // Register pending requests as startThread() would
        prepareRuntimeForThreadStart(runtime, requestID: 100)
        prepareRuntimeForThreadStart(runtime, requestID: 101)

        // 1. Delayed thread/started notification for session A
        runtime.simulateLine(threadStartedNotification(threadID: "session-A"))
        XCTAssertEqual(runtime.currentThreadID, "session-A")

        // 2. thread/start response for session B arrives
        runtime.simulateLine(threadStartResponse(requestID: 101, threadID: "session-B"))

        // CRITICAL: currentThreadID must be "session-B", not "session-A".
        // Before the fix, the response was silently discarded because
        // currentThreadID != nil.
        XCTAssertEqual(runtime.currentThreadID, "session-B",
                       "Response for session B must not be discarded by delayed notification from session A")

        // Session B must appear in the session list
        XCTAssertTrue(runtime.sessions.contains(where: { $0.sessionID == "session-B" }),
                      "Session B must be recorded in the session list")

        // onThreadStarted must have fired for session B
        XCTAssertTrue(threadStartedCalls.contains("session-B"),
                      "onThreadStarted must fire for session B")
    }

    // MARK: - Test: response + notification for same ID fires callback exactly once

    func test_responseAndNotificationForSameSessionIDFireCallbackExactlyOnce() throws {
        let runtime = ClaudeCodeRuntime()
        var threadStartedCalls: [String] = []
        runtime.onThreadStarted = { threadStartedCalls.append($0) }
        runtime.currentThreadID = nil

        prepareRuntimeForThreadStart(runtime, requestID: 200)

        // Response arrives first
        runtime.simulateLine(threadStartResponse(requestID: 200, threadID: "session-X"))
        XCTAssertEqual(threadStartedCalls.filter({ $0 == "session-X" }).count, 1,
                       "onThreadStarted should fire once from response")

        // Same notification arrives (idempotency)
        runtime.simulateLine(threadStartedNotification(threadID: "session-X"))
        XCTAssertEqual(threadStartedCalls.filter({ $0 == "session-X" }).count, 1,
                       "onThreadStarted must NOT fire again from duplicate notification")
    }

    // MARK: - Test: notification arrives first, then response — still fires once

    func test_notificationThenResponseForSameSessionIDFireCallbackExactlyOnce() throws {
        let runtime = ClaudeCodeRuntime()
        var threadStartedCalls: [String] = []
        runtime.onThreadStarted = { threadStartedCalls.append($0) }
        runtime.currentThreadID = nil

        prepareRuntimeForThreadStart(runtime, requestID: 300)

        // Notification arrives first
        runtime.simulateLine(threadStartedNotification(threadID: "session-Y"))
        XCTAssertEqual(threadStartedCalls.filter({ $0 == "session-Y" }).count, 1,
                       "onThreadStarted should fire once from notification")

        // Response arrives later
        runtime.simulateLine(threadStartResponse(requestID: 300, threadID: "session-Y"))
        XCTAssertEqual(threadStartedCalls.filter({ $0 == "session-Y" }).count, 1,
                       "onThreadStarted must NOT fire again from response (already processed)")
    }

    // MARK: - Test: consecutive creates produce two different session IDs

    func test_consecutiveCreatesProduceDifferentSessionIDs() throws {
        let runtime = ClaudeCodeRuntime()
        var threadStartedCalls: [String] = []
        runtime.onThreadStarted = { threadStartedCalls.append($0) }
        runtime.currentThreadID = nil

        prepareRuntimeForThreadStart(runtime, requestID: 1)
        prepareRuntimeForThreadStart(runtime, requestID: 2)

        // First session: response
        runtime.simulateLine(threadStartResponse(requestID: 1, threadID: "id-001"))
        // Second session: response
        runtime.simulateLine(threadStartResponse(requestID: 2, threadID: "id-002"))

        XCTAssertEqual(Set(threadStartedCalls), ["id-001", "id-002"],
                       "Both sessions must have unique IDs and both callbacks must fire")

        let recordedIDs = Set(runtime.sessions.map(\.sessionID))
        XCTAssertTrue(recordedIDs.contains("id-001"))
        XCTAssertTrue(recordedIDs.contains("id-002"))
    }

    // MARK: - Test: second session must NOT wait for timeout

    func test_secondSessionAppearsImmediatelyFromResponse() throws {
        let runtime = ClaudeCodeRuntime()
        var threadStartedCalls: [String] = []
        runtime.onThreadStarted = { threadStartedCalls.append($0) }
        runtime.currentThreadID = nil

        prepareRuntimeForThreadStart(runtime, requestID: 1)
        prepareRuntimeForThreadStart(runtime, requestID: 2)

        // Both responses arrive in rapid succession
        runtime.simulateLine(threadStartResponse(requestID: 1, threadID: "fast-1"))
        runtime.simulateLine(threadStartResponse(requestID: 2, threadID: "fast-2"))

        // Both should be immediately available — no polling needed
        XCTAssertEqual(threadStartedCalls.count, 2,
                       "Both sessions should be available immediately")

        XCTAssertTrue(runtime.sessions.contains(where: { $0.sessionID == "fast-1" }))
        XCTAssertTrue(runtime.sessions.contains(where: { $0.sessionID == "fast-2" }))
    }

    // MARK: - Test: new sessions are blank (no inherited messages)

    func test_newSessionsAreBlankIndependentConversations() throws {
        let runtime = ClaudeCodeRuntime()
        runtime.currentThreadID = nil

        prepareRuntimeForThreadStart(runtime, requestID: 1)

        // Simulate creating a session — snapshot should start empty
        runtime.simulateLine(threadStartResponse(requestID: 1, threadID: "blank-1"))

        // The snapshot should be empty (no inherited messages)
        XCTAssertTrue(runtime.snapshot.completedTurns.isEmpty,
                      "New session must have no completed turns")
        XCTAssertNil(runtime.snapshot.activeTurn,
                     "New session must have no active turn")
    }

    // MARK: - Test: rapid interleaved sequence (full race scenario)

    func test_rapidInterleavedSequence() throws {
        let runtime = ClaudeCodeRuntime()
        var threadStartedCalls: [String] = []
        runtime.onThreadStarted = { threadStartedCalls.append($0) }
        runtime.currentThreadID = nil

        // Register pending requests for both sessions
        prepareRuntimeForThreadStart(runtime, requestID: 1)
        prepareRuntimeForThreadStart(runtime, requestID: 2)

        // Exact sequence from the bug report:
        // 1. Session A's response
        runtime.simulateLine(threadStartResponse(requestID: 1, threadID: "A"))
        // 2. Session B's request is sent (no response yet)
        // 3. Session A's delayed notification arrives
        runtime.simulateLine(threadStartedNotification(threadID: "A"))
        // 4. Session B's response arrives
        runtime.simulateLine(threadStartResponse(requestID: 2, threadID: "B"))

        // Both sessions must be recorded
        XCTAssertTrue(runtime.sessions.contains(where: { $0.sessionID == "A" }),
                      "Session A must be recorded")
        XCTAssertTrue(runtime.sessions.contains(where: { $0.sessionID == "B" }),
                      "Session B must be recorded (was silently discarded before fix)")

        // currentThreadID must be B (the latest)
        XCTAssertEqual(runtime.currentThreadID, "B",
                       "currentThreadID must reflect the latest session")

        // Each callback fired exactly once
        XCTAssertEqual(threadStartedCalls.filter({ $0 == "A" }).count, 1)
        XCTAssertEqual(threadStartedCalls.filter({ $0 == "B" }).count, 1)
        XCTAssertEqual(threadStartedCalls.count, 2)
    }

    // MARK: - Test: notification for different session after response is ignored

    func test_notificationForDifferentSessionAfterResponseIsIgnored() throws {
        let runtime = ClaudeCodeRuntime()
        var threadStartedCalls: [String] = []
        runtime.onThreadStarted = { threadStartedCalls.append($0) }
        runtime.currentThreadID = nil

        prepareRuntimeForThreadStart(runtime, requestID: 1)

        // Response for B arrives and is processed
        runtime.simulateLine(threadStartResponse(requestID: 1, threadID: "B"))
        XCTAssertEqual(runtime.currentThreadID, "B")

        // Late notification for A arrives — should NOT overwrite B
        runtime.simulateLine(threadStartedNotification(threadID: "A"))

        // currentThreadID must still be B
        XCTAssertEqual(runtime.currentThreadID, "B",
                       "Late notification for A must not overwrite B")
        // Callback for A should NOT fire (it's a stale notification)
        XCTAssertFalse(threadStartedCalls.contains("A"),
                       "Stale notification for A must not fire callback")
    }
}
