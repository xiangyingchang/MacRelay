import XCTest
import AgentClientCore
@testable import AgentClientMacShell

@MainActor
final class SessionMessageCacheTests: XCTestCase {
    func test_newSessionDoesNotOverwritePreviousSessionMessages() {
        var cache = SessionMessageCache<ConversationMessage>()
        let firstUser = ConversationMessage(role: "User", text: "one")
        let firstReply = ConversationMessage(role: "Codex", text: "reply one")
        let secondUser = ConversationMessage(role: "User", text: "two")
        let secondReply = ConversationMessage(role: "Codex", text: "reply two")

        _ = cache.bindPendingNewSession(threadID: "019f09ed-3", currentMessages: [])
        cache.save(messages: [firstUser, firstReply], for: "019f09ed-3")

        let pending = cache.beginPendingNewSession()
        XCTAssertTrue(pending.isEmpty)

        _ = cache.bindPendingNewSession(threadID: "019f09ed-5", currentMessages: pending)
        cache.save(messages: [secondUser, secondReply], for: "019f09ed-5")

        XCTAssertEqual(cache.messages(for: "019f09ed-3").map(\.text), ["one", "reply one"])
        XCTAssertEqual(cache.messages(for: "019f09ed-5").map(\.text), ["two", "reply two"])
    }

    func test_pendingNewSessionMessageDoesNotOverwritePreviousSession() {
        var cache = SessionMessageCache<ConversationMessage>()
        let firstMessages = [
            ConversationMessage(role: "User", text: "one"),
            ConversationMessage(role: "Codex", text: "reply one")
        ]
        let pendingMessage = ConversationMessage(role: "Tool", text: "Starting new session...")

        _ = cache.bindPendingNewSession(threadID: "019f09ed-3", currentMessages: [])
        cache.save(messages: firstMessages, for: "019f09ed-3")

        _ = cache.beginPendingNewSession()
        cache.savePending([pendingMessage])
        _ = cache.bindPendingNewSession(threadID: "019f09ed-5", currentMessages: [pendingMessage])

        XCTAssertEqual(cache.messages(for: "019f09ed-3").map(\.text), ["one", "reply one"])
        XCTAssertEqual(cache.messages(for: "019f09ed-5").map(\.text), ["Starting new session..."])
    }

    func test_remoteNewSessionBindsEmptyTranscriptInsteadOfCurrentSessionMessages() {
        var cache = SessionMessageCache<ConversationMessage>()
        let oldMessages = [
            ConversationMessage(role: "User", text: "old question"),
            ConversationMessage(role: "Codex", text: "old answer")
        ]

        cache.save(messages: oldMessages, for: "old-thread")
        let clearedMessages = cache.beginPendingNewSession()
        let newMessages = cache.bindPendingNewSession(
            threadID: "new-thread",
            currentMessages: oldMessages
        )

        XCTAssertTrue(clearedMessages.isEmpty)
        XCTAssertTrue(newMessages.isEmpty)
        XCTAssertEqual(cache.messages(for: "old-thread").map(\.text), ["old question", "old answer"])
        XCTAssertTrue(cache.messages(for: "new-thread").isEmpty)
    }

    func test_failedRemoteNewSessionCanRestorePreviousTranscript() {
        var cache = SessionMessageCache<ConversationMessage>()
        let oldMessages = [ConversationMessage(role: "User", text: "keep me")]
        cache.save(messages: oldMessages, for: "old-thread")

        _ = cache.beginPendingNewSession()
        cache.cancelPendingNewSession()

        XCTAssertEqual(cache.messages(for: "old-thread").map(\.text), ["keep me"])
        XCTAssertTrue(cache.messages(for: "failed-new-thread").isEmpty)
    }

    func test_failedRemoteNewSessionRestoresJournalOnlyTranscript() {
        let archived = [ConversationMessage(role: "User", text: "archived question")]

        let restored = SessionTranscriptRestorer.restore(
            cached: [],
            archivedWithSteps: [],
            archivedPlain: archived
        )

        XCTAssertEqual(restored.map(\.text), ["archived question"])
    }

    func test_providerReplacementRebindsNewSessionSuccessAndFailureCallbacks() {
        let firstRuntime = AgentRuntime()
        let replacementRuntime = AgentRuntime()
        var started: [String] = []
        var failures: [String] = []

        RuntimeLifecycleBinder.bind(
            runtime: firstRuntime,
            onEvent: { _ in },
            onThreadStarted: { started.append("first:\($0)") },
            onSessionStartFailed: { failures.append("first:\($0)") }
        )
        RuntimeLifecycleBinder.bind(
            runtime: replacementRuntime,
            onEvent: { _ in },
            onThreadStarted: { started.append("replacement:\($0)") },
            onSessionStartFailed: { failures.append("replacement:\($0)") }
        )

        replacementRuntime.onThreadStarted?("new-thread")
        replacementRuntime.reportSessionStartFailure("start failed")

        XCTAssertEqual(started, ["replacement:new-thread"])
        XCTAssertEqual(failures, ["replacement:start failed"])
    }
}
