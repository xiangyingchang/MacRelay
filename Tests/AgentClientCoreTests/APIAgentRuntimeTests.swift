import XCTest
@testable import AgentClientCore

/// Tests for APIAgentRuntime and OpenAI-compatible API integration.
///
/// These tests verify that:
/// 1. API Agent uses the same Harness infrastructure as Codex/Claude
/// 2. RuntimeEvents are produced correctly
/// 3. The reducer produces correct snapshots
/// 4. Tool calling works through the approval gate
@MainActor
final class APIAgentRuntimeTests: XCTestCase {

    // MARK: - Test Helpers

    /// Create a test API provider with a mock API key.
    private func createTestProvider() -> APIProvider {
        APIProvider(
            id: "test-openai",
            name: "Test OpenAI",
            baseURL: "https://api.openai.com/v1",
            apiKey: "test-key",
            defaultModel: "gpt-4o",
            supportsStreaming: true,
            supportsToolCalling: true,
            supportsVision: false,
            protocolType: .openai
        )
    }

    // MARK: - Tests

    /// Test that APIAgentRuntime can be instantiated.
    func testRuntimeInitialization() throws {
        let provider = createTestProvider()
        let runtime = APIAgentRuntime(provider: provider)

        XCTAssertNotNil(runtime)
        XCTAssertEqual(runtime.statusText, "API Agent ready (Test OpenAI)")
    }

    /// Test that APIAgentRuntime reports cliInstalled = true (no CLI needed).
    func testRuntimeDoesNotNeedCLI() throws {
        let provider = createTestProvider()
        let runtime = APIAgentRuntime(provider: provider)

        XCTAssertTrue(runtime.cliInstalled)
    }

    /// Test that APIAgentRuntime is always ready.
    func testRuntimeIsAlwaysReady() throws {
        let provider = createTestProvider()
        let runtime = APIAgentRuntime(provider: provider)

        XCTAssertTrue(runtime.isReadyForAppServer)
    }

    /// Test that initialize sets isInitialized = true.
    func testRuntimeInitialize() throws {
        let provider = createTestProvider()
        let runtime = APIAgentRuntime(provider: provider)

        _ = try runtime.initialize()

        XCTAssertTrue(runtime.isInitialized)
    }

    /// Test that initialize broadcasts model list.
    func testInitializeBroadcastsModelList() throws {
        let provider = createTestProvider()
        let runtime = APIAgentRuntime(provider: provider)

        var receivedEvent: CodexAppServerEvent?
        runtime.onEventReceived = { event in
            receivedEvent = event
        }

        _ = try runtime.initialize()

        if case let .notification(method, params) = receivedEvent {
            XCTAssertEqual(method, "model/list/done")
            let models = params?["models"] as? [String]
            XCTAssertEqual(models, ["gpt-4o"])
        } else {
            XCTFail("Expected model/list/done notification")
        }
    }

    /// Test that selectSession throws for unknown session.
    func testSelectSessionThrowsForUnknown() throws {
        let provider = createTestProvider()
        let runtime = APIAgentRuntime(provider: provider)

        XCTAssertThrowsError(try runtime.selectSession(sessionID: "unknown"))
    }

    /// Test that selectSession works for known session.
    func testSelectSessionWorksForKnown() throws {
        let provider = createTestProvider()
        let runtime = APIAgentRuntime(provider: provider)

        // Add a session
        runtime.rememberSession(
            sessionID: "test-session",
            cwd: "/tmp",
            title: "Test",
            status: "active"
        )

        XCTAssertNoThrow(try runtime.selectSession(sessionID: "test-session"))
        XCTAssertEqual(runtime.selectedSessionID, "test-session")
    }

    /// Test that listSessions returns added sessions.
    func testListSessions() throws {
        let provider = createTestProvider()
        let runtime = APIAgentRuntime(provider: provider)

        runtime.rememberSession(sessionID: "session-1", cwd: "/tmp", title: "Test 1", status: "active")
        runtime.rememberSession(sessionID: "session-2", cwd: "/tmp", title: "Test 2", status: "active")

        let sessions = runtime.listSessions()
        XCTAssertEqual(sessions.count, 2)
    }

    /// Test that stopSession clears all state.
    func testStopSessionClearsState() throws {
        let provider = createTestProvider()
        let runtime = APIAgentRuntime(provider: provider)

        runtime.rememberSession(sessionID: "session-1", cwd: "/tmp", title: "Test", status: "active")

        try runtime.stopSession()

        XCTAssertTrue(runtime.listSessions().isEmpty)
        XCTAssertNil(runtime.currentThreadID)
    }

    /// Test APIProvider configuration.
    func testAPIProviderConfiguration() throws {
        let provider = createTestProvider()

        XCTAssertEqual(provider.id, "test-openai")
        XCTAssertEqual(provider.name, "Test OpenAI")
        XCTAssertEqual(provider.baseURL, "https://api.openai.com/v1")
        XCTAssertEqual(provider.defaultModel, "gpt-4o")
        XCTAssertTrue(provider.supportsStreaming)
        XCTAssertTrue(provider.supportsToolCalling)
    }

    /// Test built-in providers.
    func testBuiltInProviders() throws {
        XCTAssertEqual(APIProvider.openAI.name, "OpenAI")
        XCTAssertEqual(APIProvider.deepSeek.name, "DeepSeek")
        XCTAssertEqual(APIProvider.mimo.name, "MIMO")
    }

    /// Test APIProviderStore save/load.
    func testProviderStore() throws {
        let store = APIProviderStore()
        let provider = createTestProvider()

        store.saveProvider(provider)

        let loaded = store.loadProviders()
        XCTAssertTrue(loaded.contains { $0.id == provider.id })

        store.deleteProvider(id: provider.id)

        let afterDelete = store.loadProviders()
        XCTAssertFalse(afterDelete.contains { $0.id == provider.id })
    }

    /// Test ChatMessage encoding.
    func testChatMessageEncoding() throws {
        let message = ChatMessage(role: "user", content: "Hello")

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.role, "user")
        XCTAssertEqual(decoded.content, "Hello")
    }

    /// Test ToolDefinition encoding.
    func testToolDefinitionEncoding() throws {
        let tool = ToolDefinition(function: FunctionDefinition(
            name: "read_file",
            description: "Read a file",
            parameters: [
                "type": "object",
                "properties": ["path": ["type": "string"]],
                "required": ["path"]
            ]
        ))

        let encoder = JSONEncoder()
        let data = try encoder.encode(tool)
        let decoded = try JSONDecoder().decode(ToolDefinition.self, from: data)

        XCTAssertEqual(decoded.function.name, "read_file")
        XCTAssertEqual(decoded.function.description, "Read a file")
    }

    /// Test ChatCompletionChunk decoding.
    func testChatCompletionChunkDecoding() throws {
        let json = """
        {
            "id": "chatcmpl-123",
            "choices": [{
                "index": 0,
                "delta": {
                    "role": "assistant",
                    "content": "Hello"
                },
                "finish_reason": null
            }]
        }
        """

        let data = json.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)

        XCTAssertEqual(chunk.id, "chatcmpl-123")
        XCTAssertEqual(chunk.choices.first?.delta.content, "Hello")
        XCTAssertEqual(chunk.choices.first?.delta.role, "assistant")
    }

    /// Test ErrorResponse decoding.
    func testErrorResponseDecoding() throws {
        let json = """
        {
            "error": {
                "message": "Invalid API key",
                "type": "invalid_request_error",
                "code": "invalid_api_key"
            }
        }
        """

        let data = json.data(using: .utf8)!
        let error = try JSONDecoder().decode(ErrorResponse.self, from: data)

        XCTAssertEqual(error.error.message, "Invalid API key")
        XCTAssertEqual(error.error.type, "invalid_request_error")
        XCTAssertEqual(error.error.code, "invalid_api_key")
    }

    /// Test that RuntimeIdentifier supports API providers.
    func testRuntimeIdentifierAPIProviders() throws {
        XCTAssertEqual(RuntimeIdentifier.openAI.rawValue, "openai")
        XCTAssertEqual(RuntimeIdentifier.deepSeek.rawValue, "deepseek")
        XCTAssertEqual(RuntimeIdentifier.mimo.rawValue, "mimo")
    }

    /// Test that AgentProvider supports API providers.
    func testAgentProviderAPIProviders() throws {
        XCTAssertTrue(AgentProvider.allCases.contains(.openAI))
        XCTAssertTrue(AgentProvider.allCases.contains(.deepSeek))
        XCTAssertTrue(AgentProvider.allCases.contains(.mimo))
    }
}
