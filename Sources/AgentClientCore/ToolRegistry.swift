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

// MARK: - Tool Approval Status

/// The approval status of a tool execution request.
public enum ToolApprovalStatus: Equatable {
    /// Policy allowed execution; the tool ran.
    case allowed
    /// Policy requires user approval; execution is pending.
    case pendingApproval(requestID: Int)
    /// Policy denied execution.
    case denied
}

/// The result of a tool execution attempt through the policy-aware registry.
///
/// Wraps the underlying `ToolResult` with approval context so callers know
/// whether the tool was actually executed, is waiting for approval, or was denied.
public struct ToolApprovalResult: Equatable {
    /// The approval status.
    public let status: ToolApprovalStatus
    /// The underlying tool result (present when status is `.allowed`).
    public let toolResult: ToolResult?
    /// The policy evaluation that determined the approval status.
    public let evaluation: PolicyEvaluationResult

    /// The call ID from the original tool call.
    public var callID: String { toolResult?.callID ?? "" }
    /// Whether the tool executed successfully.
    public var success: Bool { toolResult?.success ?? false }
    /// Output from the tool (present on successful execution).
    public var output: String? { toolResult?.output }
    /// Error message (present on failure or denial).
    public var error: String? {
        if let toolError = toolResult?.error { return toolError }
        switch status {
        case .denied:
            return "Tool execution denied: \(evaluation.reason)"
        case .pendingApproval:
            return nil
        case .allowed:
            return nil
        }
    }

    public init(status: ToolApprovalStatus, toolResult: ToolResult?, evaluation: PolicyEvaluationResult) {
        self.status = status
        self.toolResult = toolResult
        self.evaluation = evaluation
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

    /// Optional policy engine for approval evaluation.
    /// When set, `executeWithApproval()` evaluates the policy before execution.
    public var policyEngine: ApprovalPolicyEngine?

    /// Auto-incrementing request ID for approval requests.
    private var nextApprovalRequestID: Int = 1

    // MARK: - Initialization

    public init(policyEngine: ApprovalPolicyEngine? = nil) {
        self.policyEngine = policyEngine
    }

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

    /// Execute a tool call with policy evaluation.
    ///
    /// This is the primary execution method. It:
    /// 1. Validates the tool exists and parameters are correct
    /// 2. Evaluates the approval policy (if a policy engine is set)
    /// 3. For `.allow`: executes immediately
    /// 4. For `.ask`: returns a pending-approval result (caller handles UI)
    /// 5. For `.deny`: returns a denied result without executing
    ///
    /// - Parameters:
    ///   - call: The tool call to execute.
    ///   - context: Execution context (workspace, session, run info).
    /// - Returns: A `ToolApprovalResult` wrapping the execution outcome.
    public func executeWithApproval(
        call: ToolCall,
        context: ToolExecutionContext
    ) async throws -> ToolApprovalResult {
        // Check tool exists
        guard let registration = registrations[call.name] else {
            let errorResult = ToolResult(
                callID: call.id,
                success: false,
                error: ToolExecutionError.toolNotFound(call.name).localizedDescription
            )
            let fallbackEval = PolicyEvaluationResult(
                decision: .deny,
                rule: "tool_not_found",
                reason: "Tool not found: \(call.name)"
            )
            return ToolApprovalResult(
                status: .denied,
                toolResult: errorResult,
                evaluation: fallbackEval
            )
        }

        // Validate required parameters
        if let validationError = validateParameters(call: call, definition: registration.definition) {
            let errorResult = ToolResult(
                callID: call.id,
                success: false,
                error: validationError.localizedDescription
            )
            let fallbackEval = PolicyEvaluationResult(
                decision: .deny,
                rule: "validation_failed",
                reason: validationError.localizedDescription
            )
            return ToolApprovalResult(
                status: .denied,
                toolResult: errorResult,
                evaluation: fallbackEval
            )
        }

        // Evaluate approval policy
        let evaluation: PolicyEvaluationResult
        if let engine = policyEngine {
            evaluation = engine.evaluate(tool: registration.definition, call: call, context: context)
        } else {
            // No policy engine: use tool default
            evaluation = PolicyEvaluationResult(
                decision: registration.definition.defaultApprovalPolicy,
                rule: "tool_default",
                reason: "No policy engine configured; using tool default"
            )
        }

        // Act on the policy decision
        switch evaluation.decision {
        case .allow:
            // Track execution
            executionCounts[call.name, default: 0] += 1

            // Execute
            do {
                let result = try await registration.executor.execute(call: call, context: context)
                return ToolApprovalResult(
                    status: .allowed,
                    toolResult: result,
                    evaluation: evaluation
                )
            } catch {
                let errorResult = ToolResult(
                    callID: call.id,
                    success: false,
                    error: error.localizedDescription
                )
                return ToolApprovalResult(
                    status: .allowed,
                    toolResult: errorResult,
                    evaluation: evaluation
                )
            }

        case .ask:
            // Generate a request ID for the pending approval
            let requestID = nextApprovalRequestID
            nextApprovalRequestID += 1
            return ToolApprovalResult(
                status: .pendingApproval(requestID: requestID),
                toolResult: nil,
                evaluation: evaluation
            )

        case .deny:
            return ToolApprovalResult(
                status: .denied,
                toolResult: nil,
                evaluation: evaluation
            )
        }
    }

    /// Execute a tool call (backward-compatible convenience method).
    ///
    /// This is a thin wrapper around `executeWithApproval()` that discards
    /// approval context and returns a plain `ToolResult`. Use
    /// `executeWithApproval()` when you need policy evaluation details.
    public func execute(call: ToolCall, context: ToolExecutionContext) async throws -> ToolResult {
        let approvalResult = try await executeWithApproval(call: call, context: context)
        if let toolResult = approvalResult.toolResult {
            return toolResult
        }
        // Denied or pending: synthesize a failed ToolResult
        return ToolResult(
            callID: call.id,
            success: false,
            error: approvalResult.error
        )
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
