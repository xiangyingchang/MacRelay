import XCTest
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
}
