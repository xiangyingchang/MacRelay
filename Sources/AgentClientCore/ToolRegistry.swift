import Foundation

// MARK: - ToolResult → RuntimeEvent Bridge

extension ToolResult {
    /// Convert a successful tool result into a RuntimeEvent.
    public func toCompletedEvent(runtime: RuntimeIdentifier, sessionID: String? = nil, runID: String? = nil) -> RuntimeEvent {
        RuntimeEvent(
            sessionID: sessionID,
            runID: runID,
            runtime: runtime,
            type: .toolCallCompleted,
            payload: .toolCallCompleted(name: callID, result: output)
        )
    }

    /// Convert a failed tool result into a RuntimeEvent.
    public func toFailedEvent(runtime: RuntimeIdentifier, toolName: String, sessionID: String? = nil, runID: String? = nil) -> RuntimeEvent {
        RuntimeEvent(
            sessionID: sessionID,
            runID: runID,
            runtime: runtime,
            type: .toolCallFailed,
            payload: .toolCallFailed(name: toolName, error: error ?? "Unknown error")
        )
    }

    /// Convert a tool result into the appropriate RuntimeEvent (completed or failed).
    public func toRuntimeEvent(runtime: RuntimeIdentifier, toolName: String, sessionID: String? = nil, runID: String? = nil) -> RuntimeEvent {
        if success {
            return toCompletedEvent(runtime: runtime, sessionID: sessionID, runID: runID)
        } else {
            return toFailedEvent(runtime: runtime, toolName: toolName, sessionID: sessionID, runID: runID)
        }
    }
}

// MARK: - Tool Registry

/// Central registry for tool definitions and executors.
///
/// The ToolRegistry is the single source of truth for:
/// - Tool discovery (what tools are available)
/// - Tool metadata (risk level, approval policy, capabilities)
/// - Tool execution (dispatching calls to executors)
/// - Execution tracking (call counts per tool)
///
/// This replaces the inline tool definitions previously in APIAgentRuntime.
public final class ToolRegistry {
    // MARK: - Types

    private struct Registration {
        let definition: ToolDefinition
        let executor: ToolExecutor
    }

    // MARK: - State

    private var registrations: [String: Registration] = [:]
    private var executionCounts: [String: Int] = [:]

    // MARK: - Initialization

    public init() {}

    // MARK: - Registration

    /// Register a tool with its definition and executor.
    ///
    /// If a tool with the same name already exists, it is replaced.
    public func register(tool definition: ToolDefinition, executor: ToolExecutor) {
        let name = definition.name
        registrations[name] = Registration(definition: definition, executor: executor)
        if executionCounts[name] == nil {
            executionCounts[name] = 0
        }
    }

    /// Unregister a tool by name.
    ///
    /// Returns `true` if the tool was found and removed, `false` otherwise.
    @discardableResult
    public func unregister(name: String) -> Bool {
        let removed = registrations.removeValue(forKey: name) != nil
        executionCounts.removeValue(forKey: name)
        return removed
    }

    // MARK: - Lookup

    /// Get the definition for a tool by name.
    public func definition(name: String) -> ToolDefinition? {
        registrations[name]?.definition
    }

    /// List all registered tool definitions.
    public func listTools() -> [ToolDefinition] {
        registrations.values.map(\.definition).sorted { $0.name < $1.name }
    }

    /// Get the execution count for a tool.
    public func executionCount(for toolName: String) -> Int {
        executionCounts[toolName] ?? 0
    }

    /// Get execution counts for all tools.
    public func allExecutionCounts() -> [String: Int] {
        executionCounts
    }

    /// Check if a tool is registered.
    public func hasTool(name: String) -> Bool {
        registrations[name] != nil
    }

    // MARK: - Execution

    /// Execute a tool call.
    ///
    /// Validates that:
    /// 1. The tool exists
    /// 2. Required parameters are present
    ///
    /// Then delegates to the registered executor.
    public func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        // Check tool exists
        guard let registration = registrations[call.name] else {
            return ToolResult(
                callID: call.id,
                success: false,
                error: ToolExecutionError.toolNotFound(call.name).localizedDescription
            )
        }

        // Validate required parameters
        if let validationError = validateParameters(call: call, definition: registration.definition) {
            return ToolResult(
                callID: call.id,
                success: false,
                error: validationError.localizedDescription
            )
        }

        // Track execution
        executionCounts[call.name, default: 0] += 1

        // Execute
        do {
            return try await registration.executor.execute(call: call, context: context)
        } catch {
            return ToolResult(
                callID: call.id,
                success: false,
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Parameter Validation

    /// Validate that required parameters are present in the tool call.
    ///
    /// This performs basic validation: checks that parameters declared as
    /// "required" in the input schema are present. It does NOT validate
    /// types or values (that's the executor's job).
    private func validateParameters(call: ToolCall, definition: ToolDefinition) -> ToolExecutionError? {
        guard let inputSchema = definition.inputSchema else {
            return nil
        }

        // Extract required params from schema.
        // The value may be [String] (plain) or [AnyCodable] (after Codable round-trip).
        let requiredArray: [String]?
        if let strings = inputSchema["required"]?.value as? [String] {
            requiredArray = strings
        } else if let codables = inputSchema["required"]?.value as? [AnyCodable] {
            requiredArray = codables.compactMap { $0.value as? String }
        } else {
            requiredArray = nil
        }

        guard let required = requiredArray else {
            return nil
        }

        for requiredParam in required {
            if call.parameters[requiredParam] == nil {
                return .missingParameter(requiredParam)
            }
        }

        return nil
    }
}
