import XCTest
@testable import AgentClientCore

// MARK: - Regression tests for empty session snapshot messages
//
// Root cause: Mac snapshot.get handler only set messages when non-empty:
//   if let msgs, !msgs.isEmpty { session.messages = msgs }
// This turned messages=[] into messages=nil in JSON. iOS then fell back
// to snap.turns (global reducer data from the previous session).
//
// Fix: Mac always sets messages (including []). iOS distinguishes:
//   messages=[] → empty session (show blank page)
//   messages=nil → old protocol (fall back to turns)

@MainActor
final class EmptySessionSnapshotTests: XCTestCase {

    private func makeSessionPayload(
        threadID: String,
        messages: [RelayConversationMessagePayload]?,
        turns: [RelayTurnSnapshotPayload] = []
    ) -> RelaySessionSnapshotPayload {
        RelaySessionSnapshotPayload(
            threadID: threadID,
            cwd: "/tmp",
            status: "idle",
            model: nil,
            effort: nil,
            assistantText: turns.isEmpty ? "" : "old text",
            turns: turns,
            changedFiles: [],
            messages: messages
        )
    }

    // MARK: - Test: messages=[] must not fall back to turns

    func test_emptyMessagesArrayDoesNotFallbackToTurns() {
        let payload = makeSessionPayload(
            threadID: "new-session",
            messages: [],
            turns: [RelayTurnSnapshotPayload(
                id: "old-session",
                userMessage: "old question",
                assistantText: "old answer",
                isCompleted: true
            )]
        )

        XCTAssertNotNil(payload.messages,
                        "messages=[] must be non-nil so iOS doesn't fall back to turns")
        XCTAssertTrue(payload.messages!.isEmpty,
                     "messages=[] must be empty for a new session")
    }

    // MARK: - Test: messages=nil falls back to turns (old protocol)

    func test_nilMessagesFallsBackToTurns() {
        let payload = makeSessionPayload(
            threadID: "old-session",
            messages: nil,
            turns: [RelayTurnSnapshotPayload(
                id: "turn-1",
                userMessage: "question",
                assistantText: "answer",
                isCompleted: true
            )]
        )

        XCTAssertNil(payload.messages,
                     "messages=nil means old protocol — iOS should use turns fallback")
        XCTAssertFalse(payload.turns.isEmpty,
                       "turns should have data for the turns fallback path")
    }

    // MARK: - Test: session with actual messages

    func test_nonEmptyMessagesArePreserved() {
        let msgs = [
            RelayConversationMessagePayload(role: "User", text: "hello"),
            RelayConversationMessagePayload(role: "Assistant", text: "hi there")
        ]
        let payload = makeSessionPayload(threadID: "active-session", messages: msgs)

        XCTAssertEqual(payload.messages?.count, 2)
        XCTAssertEqual(payload.messages?.first?.text, "hello")
    }

    // MARK: - Test: activeSessionID alignment

    func test_activeSessionIDMatchesThreadID() {
        var payload = RelaySnapshotPayload(
            activeSessionID: "A",
            session: makeSessionPayload(threadID: "A", messages: nil),
            connection: ConnectionSnapshotPayload(isPaired: true, isOnline: true),
            pendingApprovals: [],
            lastEventSeq: 0
        )

        // Simulate what broadcastGroupedSnapshot does
        payload.activeSessionID = "B"
        payload.session?.threadID = "B"

        XCTAssertEqual(payload.activeSessionID, "B")
        XCTAssertEqual(payload.session?.threadID, "B",
                       "activeSessionID and session.threadID must be aligned")
    }

    // MARK: - Test: encode/decode roundtrip preserves messages=[]

    func test_encodeDecodePreservesEmptyMessages() throws {
        let original = makeSessionPayload(threadID: "test", messages: [])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RelaySessionSnapshotPayload.self, from: data)

        XCTAssertNotNil(decoded.messages,
                        "Decoded messages must not be nil when original was []")
        XCTAssertTrue(decoded.messages!.isEmpty,
                     "Decoded messages must be empty when original was []")
    }

    // MARK: - Test: encode/decode roundtrip preserves messages=nil

    func test_encodeDecodePreservesNilMessages() throws {
        let original = makeSessionPayload(threadID: "test", messages: nil)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RelaySessionSnapshotPayload.self, from: data)

        XCTAssertNil(decoded.messages,
                     "Decoded messages must be nil when original was nil")
    }
}
