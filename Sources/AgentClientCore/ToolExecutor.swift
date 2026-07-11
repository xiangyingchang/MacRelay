import Foundation

// MARK: - Tool Executor Protocol

/// Protocol for implementing tool execution logic.
///
/// Each tool in the registry has an associated `ToolExecutor` that handles
/// the actual execution. Implementations should be stateless where possible.
public protocol ToolExecutor {
    /// The name of the tool this executor handles.
    var toolName: String { get }

    /// Execute the tool call with the given context.
    ///
    /// - Parameters:
    ///   - call: The tool call to execute.
    ///   - context: Execution context (workspace path, session info).
    /// - Returns: The result of the tool execution.
    /// - Throws: Any error during execution (will be wrapped in a failed ToolResult).
    func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult
}

// MARK: - Tool Execution Error

/// Errors that can occur during tool execution.
public enum ToolExecutionError: Error, LocalizedError {
    case toolNotFound(String)
    case missingParameter(String)
    case executionFailed(String)
    case denied(String)

    public var errorDescription: String? {
        switch self {
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .missingParameter(let param):
            return "Missing required parameter: \(param)"
        case .executionFailed(let reason):
            return "Tool execution failed: \(reason)"
        case .denied(let reason):
            return "Tool execution denied: \(reason)"
        }
    }
}
