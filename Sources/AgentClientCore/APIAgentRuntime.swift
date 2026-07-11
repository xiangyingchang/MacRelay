import Foundation

// MARK: - API Agent Runtime

/// Runtime implementation for OpenAI-compatible API providers.
///
/// This runtime allows MacRelay to work with API-based models (OpenAI, DeepSeek, MIMO)
/// using the same Harness infrastructure as Codex/Claude Code.
///
/// Architecture:
///   LLM Stream → APIAgentRuntime → RuntimeEvent → Trace → Reducer → Timeline
@MainActor
public final class APIAgentRuntime: AgentRuntime {
    // MARK: - Properties

    private let provider: APIProvider
    private var client: OpenAICompatibleClient
    private let reducer = SessionStateReducer()
    private var currentTask: Task<Void, Never>?

    /// Conversation history for the current session.
    private var conversationHistory: [ChatMessage] = []

    /// Available tools for the agent.
    private var availableTools: [ToolDefinition] = []

    /// Current turn ID (generated locally for API mode).
    private var currentTurnID: String?

    // MARK: - Initialization

    public init(provider: APIProvider) {
        self.provider = provider
        self.client = OpenAICompatibleClient(provider: provider)
        super.init()
        statusText = "API Agent ready (\(provider.name))"
        setupTools()
    }

    // MARK: - AgentRuntime Overrides

    override public var cliInstalled: Bool {
        // API runtime doesn't need a CLI
        true
    }

    override public var isReadyForAppServer: Bool {
        // API runtime is always ready (no app-server needed)
        true
    }

    override public func refreshDetection() {
        // API runtime doesn't need detection
        statusText = "API Agent ready (\(provider.name))"
    }

    override public func startAppServer(cwd: String) throws {
        // API runtime doesn't use an app-server
        isAppServerRunning = true
        statusText = "API Agent ready"
    }

    override public func stopAppServer() {
        currentTask?.cancel()
        currentTask = nil
        isAppServerRunning = false
        isInitialized = false
        currentThreadID = nil
        latestTurnID = nil
        conversationHistory.removeAll()
        statusText = "API Agent stopped"
    }

    override public func initialize() throws -> Int {
        isInitializing = true
        isInitialized = true
        isInitializing = false
        statusText = "API Agent initialized"

        // Broadcast model list
        modelNames = [provider.defaultModel].compactMap { $0 }
        let modelEvent = CodexAppServerEvent.notification(
            method: "model/list/done",
            params: ["models": modelNames]
        )
        onEventReceived?(modelEvent)

        return 0
    }

    override public func enqueueDraft(
        cwd: String,
        text: String,
        model: String?,
        effort: String?,
        threadSandbox: String,
        turnSandbox: String,
        approvalPolicy: String
    ) throws {
        // Ensure initialized
        if !isInitialized {
            _ = try initialize()
        }

        // Create thread if needed
        if currentThreadID == nil {
            let threadID = "api-session-\(UUID().uuidString.prefix(8))"
            currentThreadID = threadID

            // Record session
            let session = RelaySessionInfoPayload(
                sessionID: threadID,
                cwd: cwd,
                model: model ?? provider.defaultModel,
                effort: effort,
                status: "active",
                createdAt: Date(),
                title: String(text.prefix(50))
            )
            sessions.append(session)

            // Emit thread/started event
            let threadEvent = CodexAppServerEvent.notification(
                method: "thread/started",
                params: [
                    "id": threadID,
                    "cwd": cwd,
                    "status": ["type": "active"]
                ]
            )
            onEventReceived?(threadEvent)
            onThreadStarted?(threadID)
        }

        // Start turn
        try startTurn(
            threadID: currentThreadID!,
            text: text,
            model: model,
            effort: effort,
            approvalPolicy: approvalPolicy
        )
    }

    /// Start a new turn in the API agent.
    public func startTurn(
        threadID: String,
        text: String,
        model: String?,
        effort: String?,
        approvalPolicy: String?
    ) throws {
        let turnID = "turn-\(UUID().uuidString.prefix(8))"
        currentTurnID = turnID
        latestTurnID = turnID

        // Emit turn/started event
        let turnStartedEvent = CodexAppServerEvent.notification(
            method: "turn/started",
            params: [
                "turn_id": turnID,
                "input": text
            ]
        )
        onEventReceived?(turnStartedEvent)

        // Add user message to history
        conversationHistory.append(ChatMessage(role: "user", content: text))

        // Start streaming completion
        currentTask = Task {
            await streamCompletion(
                turnID: turnID,
                model: model ?? provider.defaultModel ?? "gpt-4o",
                approvalPolicy: approvalPolicy
            )
        }
    }

    override public func resolveApproval(requestID: Int, decision: String) throws {
        // Find the pending approval
        guard var approval = snapshot.pendingApprovals[String(requestID)] else {
            return
        }

        // Update approval state
        approval.decision = decision
        approval.isPending = false

        // Apply to reducer
        let action = SessionReducerAction.approvalResolved(requestID: requestID, decision: decision)
        var nextSnapshot = snapshot
        reducer.reduce(&nextSnapshot, action: action)
        snapshot = nextSnapshot

        statusText = "approval \(decision)"

        // If approved, continue the tool call
        if decision == "allow" || decision == "allow_once" {
            // The tool will be executed in the next completion cycle
            Task {
                await continueAfterApproval(requestID: requestID)
            }
        }
    }

    override public func updateSettings(
        model: String?,
        effort: String?,
        approvalPolicy: String?,
        sandboxPolicy: String?
    ) throws -> Int {
        // API runtime doesn't need settings updates to the provider
        statusText = "settings updated"
        return 0
    }

    override public func listSessions() -> [RelaySessionInfoPayload] {
        sessions
    }

    override public func rememberSession(sessionID: String, cwd: String?, title: String?, status: String?) {
        if !sessions.contains(where: { $0.sessionID == sessionID }) {
            sessions.append(RelaySessionInfoPayload(
                sessionID: sessionID,
                cwd: cwd,
                model: provider.defaultModel,
                effort: nil,
                status: status ?? "saved",
                createdAt: nil,
                title: title
            ))
        }
    }

    override public func stopSession() throws {
        currentTask?.cancel()
        currentTask = nil
        conversationHistory.removeAll()
        currentThreadID = nil
        currentTurnID = nil
        sessions.removeAll()
        statusText = "session stopped"
    }

    override public func clearCurrentThread() {
        currentTask?.cancel()
        currentTask = nil
        conversationHistory.removeAll()
        currentThreadID = nil
        currentTurnID = nil
        statusText = "thread cleared"
    }

    override public func selectSession(sessionID: String) throws {
        guard sessions.contains(where: { $0.sessionID == sessionID }) else {
            throw APIAgentError.sessionNotFound("Session \(sessionID) not found")
        }
        selectedSessionID = sessionID
        currentThreadID = sessionID
        latestTurnID = nil
        conversationHistory.removeAll()
        statusText = "session selected: \(sessionID)"
    }

    // MARK: - Private: Streaming Completion

    private func streamCompletion(turnID: String, model: String, approvalPolicy: String?) async {
        do {
            let stream = try await client.chatCompletion(
                messages: conversationHistory,
                model: model,
                tools: availableTools.isEmpty ? nil : availableTools,
                stream: true
            )

            var accumulatedContent = ""
            var pendingToolCalls: [ToolCall] = []

            for try await chunk in stream {
                guard let choice = chunk.choices.first else { continue }

                // Handle content delta
                if let content = choice.delta.content, !content.isEmpty {
                    accumulatedContent += content

                    // Emit assistant delta event
                    let deltaEvent = CodexAppServerEvent.notification(
                        method: "item/agentMessage/delta",
                        params: ["delta": content]
                    )
                    onEventReceived?(deltaEvent)
                }

                // Handle tool calls
                if let toolCalls = choice.delta.toolCalls {
                    for toolCall in toolCalls {
                        // Accumulate tool call arguments
                        if let existingIndex = pendingToolCalls.firstIndex(where: { $0.id == toolCall.id }) {
                            var existing = pendingToolCalls[existingIndex]
                            let updatedFunction = FunctionCall(
                                name: existing.function.name + toolCall.function.name,
                                arguments: existing.function.arguments + toolCall.function.arguments
                            )
                            pendingToolCalls[existingIndex] = ToolCall(
                                id: existing.id,
                                function: updatedFunction
                            )
                        } else {
                            pendingToolCalls.append(toolCall)
                        }
                    }
                }

                // Check for finish reason
                if let finishReason = choice.finishReason {
                    if finishReason == "tool_calls" {
                        // Execute tool calls
                        await executeToolCalls(
                            toolCalls: pendingToolCalls,
                            turnID: turnID,
                            approvalPolicy: approvalPolicy
                        )
                        return
                    } else if finishReason == "stop" {
                        // Turn complete
                        await completeTurn(
                            turnID: turnID,
                            content: accumulatedContent
                        )
                        return
                    }
                }
            }

            // If we get here without a finish reason, complete the turn
            if !accumulatedContent.isEmpty {
                await completeTurn(turnID: turnID, content: accumulatedContent)
            }

        } catch {
            // Emit error event
            let errorEvent = CodexAppServerEvent.notification(
                method: "error",
                params: [
                    "error": [
                        "message": error.localizedDescription,
                        "code": "api_error"
                    ]
                ]
            )
            onEventReceived?(errorEvent)
            statusText = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Private: Tool Execution

    private func executeToolCalls(
        toolCalls: [ToolCall],
        turnID: String,
        approvalPolicy: String?
    ) async {
        for toolCall in toolCalls {
            let functionName = toolCall.function.name
            let arguments = toolCall.function.arguments

            // Parse arguments
            guard let argsData = arguments.data(using: .utf8),
                  let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
                continue
            }

            // Check if approval is needed
            let needsApproval = checkApprovalNeeded(
                function: functionName,
                arguments: args,
                approvalPolicy: approvalPolicy
            )

            if needsApproval {
                // Request approval
                let requestID = Int.random(in: 1000...9999)
                let approvalRequest = CodexAppServerEvent.serverRequest(
                    id: requestID,
                    method: "requestApproval_\(functionName)",
                    params: [
                        "command": "\(functionName)(\(args))",
                        "reason": "Agent wants to call \(functionName)"
                    ]
                )
                onEventReceived?(approvalRequest)

                // Wait for approval (in a real implementation, this would be async)
                // For now, we'll auto-approve in non-blocking mode
                if approvalPolicy == "never" {
                    // Auto-approve
                    try? resolveApproval(requestID: requestID, decision: "allow")
                }
            } else {
                // Execute tool directly
                await executeTool(function: functionName, arguments: args, toolCallId: toolCall.id)
            }
        }

        // After all tools executed, continue the conversation
        let toolResults = toolCalls.map { toolCall -> ChatMessage in
            ChatMessage(
                role: "tool",
                content: "Tool executed: \(toolCall.function.name)",
                toolCallId: toolCall.id
            )
        }
        conversationHistory.append(contentsOf: toolResults)

        // Continue completion
        if let currentModel = sessions.first(where: { $0.sessionID == currentThreadID })?.model {
            currentTask = Task {
                await streamCompletion(
                    turnID: turnID,
                    model: currentModel,
                    approvalPolicy: approvalPolicy
                )
            }
        }
    }

    private func executeTool(function: String, arguments: [String: Any], toolCallId: String) async {
        // Emit tool call event
        let toolEvent = CodexAppServerEvent.notification(
            method: "tool/call/requested",
            params: [
                "name": function,
                "params": arguments
            ]
        )
        onEventReceived?(toolEvent)

        // Simulate tool execution (in real implementation, this would call actual tools)
        let result = "Tool \(function) executed"

        // Add assistant message with tool call
        conversationHistory.append(ChatMessage(
            role: "assistant",
            content: nil,
            toolCalls: [ToolCall(
                id: toolCallId,
                function: FunctionCall(
                    name: function,
                    arguments: try! String(data: JSONSerialization.data(withJSONObject: arguments), encoding: .utf8) ?? "{}"
                )
            )]
        ))

        // Emit tool completed event
        let completedEvent = CodexAppServerEvent.notification(
            method: "tool/call/completed",
            params: [
                "name": function,
                "result": result
            ]
        )
        onEventReceived?(completedEvent)
    }

    private func checkApprovalNeeded(
        function: String,
        arguments: [String: Any],
        approvalPolicy: String?
    ) -> Bool {
        // Define risk levels for different operations
        let highRiskOperations = ["write_file", "run_shell_command", "delete_file"]
        let mediumRiskOperations = ["edit_file"]

        if highRiskOperations.contains(function) {
            return approvalPolicy != "never"
        }
        if mediumRiskOperations.contains(function) {
            return approvalPolicy == "always"
        }
        return false
    }

    private func continueAfterApproval(requestID: Int) async {
        // Continue execution after approval
        // This would resume the tool execution
        statusText = "Continuing after approval"
    }

    // MARK: - Private: Turn Completion

    private func completeTurn(turnID: String, content: String) async {
        // Add assistant message to history
        conversationHistory.append(ChatMessage(role: "assistant", content: content))

        // Emit turn completed event
        let completedEvent = CodexAppServerEvent.notification(
            method: "turn/completed",
            params: ["turn_id": turnID]
        )
        onEventReceived?(completedEvent)

        // Update session title if this is the first turn
        if let threadID = currentThreadID,
           let index = sessions.firstIndex(where: { $0.sessionID == threadID }),
           (sessions[index].title ?? "").isEmpty {
            sessions[index].title = String(content.prefix(50))
        }

        currentTurnID = nil
        statusText = "Turn completed"
    }

    // MARK: - Private: Tool Setup

    private func setupTools() {
        // Define available tools for the agent
        availableTools = [
            ToolDefinition(function: FunctionDefinition(
                name: "read_file",
                description: "Read the contents of a file",
                parameters: [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "The path to the file to read"
                        ]
                    ],
                    "required": ["path"]
                ]
            )),
            ToolDefinition(function: FunctionDefinition(
                name: "write_file",
                description: "Write content to a file",
                parameters: [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "The path to the file to write"
                        ],
                        "content": [
                            "type": "string",
                            "description": "The content to write to the file"
                        ]
                    ],
                    "required": ["path", "content"]
                ]
            )),
            ToolDefinition(function: FunctionDefinition(
                name: "list_files",
                description: "List files in a directory",
                parameters: [
                    "type": "object",
                    "properties": [
                        "path": [
                            "type": "string",
                            "description": "The path to the directory to list"
                        ]
                    ],
                    "required": ["path"]
                ]
            )),
            ToolDefinition(function: FunctionDefinition(
                name: "search_text",
                description: "Search for text in files",
                parameters: [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "The text to search for"
                        ],
                        "path": [
                            "type": "string",
                            "description": "The directory to search in"
                        ]
                    ],
                    "required": ["query"]
                ]
            )),
            ToolDefinition(function: FunctionDefinition(
                name: "run_shell_command",
                description: "Run a shell command",
                parameters: [
                    "type": "object",
                    "properties": [
                        "command": [
                            "type": "string",
                            "description": "The command to run"
                        ]
                    ],
                    "required": ["command"]
                ]
            ))
        ]
    }
}

// MARK: - API Agent Error

/// Errors specific to API Agent Runtime.
public enum APIAgentError: Error, LocalizedError {
    case turnInProgress(String)
    case sessionNotFound(String)
    case runtimeUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .turnInProgress(let msg): return msg
        case .sessionNotFound(let id): return "Session not found: \(id)"
        case .runtimeUnavailable(let msg): return msg
        }
    }
}
