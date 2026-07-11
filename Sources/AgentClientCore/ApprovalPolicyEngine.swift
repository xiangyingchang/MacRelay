import Foundation

// MARK: - Approval Decision

/// The user's approval decision for a specific tool invocation.
public enum ApprovalDecision: String, Codable, Equatable {
    /// Execute this time only.
    case allowOnce
    /// Remember approval for this tool in this session/workspace.
    case alwaysAllow
    /// Deny this time.
    case reject
    /// Block this tool permanently.
    case alwaysDeny
}

// MARK: - Policy Evaluation Result

/// The outcome of evaluating a tool call against the policy engine.
public struct PolicyEvaluationResult: Equatable {
    /// The effective approval policy (allow / ask / deny).
    public let decision: ApprovalPolicy
    /// Which rule matched (e.g. "session_override", "global_rule", "tool_default").
    public let rule: String
    /// Human-readable explanation.
    public let reason: String

    public init(decision: ApprovalPolicy, rule: String, reason: String) {
        self.decision = decision
        self.rule = rule
        self.reason = reason
    }
}

// MARK: - Policy Rule

/// A declarative policy rule that maps tool patterns to approval policies.
public struct PolicyRule: Codable, Equatable {
    /// Tool name or glob pattern (e.g. "read_file", "write_*", "*").
    public let toolPattern: String
    /// Optional workspace scope. Nil means global.
    public let workspacePath: String?
    /// Optional risk level match. Nil means any risk level.
    public let riskLevel: RiskLevel?
    /// The approval policy to apply when this rule matches.
    public let policy: ApprovalPolicy
    /// Human-readable reason for this rule.
    public let reason: String

    public init(
        toolPattern: String,
        workspacePath: String? = nil,
        riskLevel: RiskLevel? = nil,
        policy: ApprovalPolicy,
        reason: String
    ) {
        self.toolPattern = toolPattern
        self.workspacePath = workspacePath
        self.riskLevel = riskLevel
        self.policy = policy
        self.reason = reason
    }
}

// MARK: - Approval Policy Engine

/// Unified policy engine for tool execution approval.
///
/// Evaluates tool calls against a prioritized rule chain:
/// 1. Session overrides (alwaysAllow / alwaysDeny from user decisions)
/// 2. Workspace policies (from .agent/policy.json -- future)
/// 3. Global policies
/// 4. Tool default (from ToolDefinition.defaultApprovalPolicy)
///
/// Critical-risk tools are NEVER auto-allowed -- they always require approval.
public final class ApprovalPolicyEngine {

    // MARK: - State

    /// Session-level overrides keyed by tool name. Highest priority.
    private var sessionOverrides: [String: ApprovalDecision] = [:]

    /// Workspace-level rules keyed by workspace path.
    private var workspaceRules: [String: [PolicyRule]] = [:]

    /// Global rules (no workspace scope).
    private var globalRules: [PolicyRule] = []

    // MARK: - Initialization

    public init() {}

    // MARK: - Evaluation

    /// Evaluate the approval policy for a tool call.
    ///
    /// The evaluation follows the priority chain. Critical-risk tools
    /// are never auto-allowed -- even an `alwaysAllow` session override
    /// is downgraded to `.ask` for critical tools.
    public func evaluate(
        tool: ToolDefinition,
        call: ToolCall,
        context: ToolExecutionContext
    ) -> PolicyEvaluationResult {
        // 1. Session overrides (highest priority)
        if let override = sessionOverrides[tool.name] {
            let effectivePolicy = effectivePolicyForOverride(override, riskLevel: tool.riskLevel)
            return PolicyEvaluationResult(
                decision: effectivePolicy,
                rule: "session_override",
                reason: "Session override: \(override.rawValue) for \(tool.name)"
            )
        }

        // 2. Workspace policies
        let workspacePath = context.workspacePath
        if let rules = workspaceRules[workspacePath] {
            if let matched = matchRule(rules: rules, tool: tool) {
                let effectivePolicy = effectivePolicyForRule(matched, riskLevel: tool.riskLevel)
                return PolicyEvaluationResult(
                    decision: effectivePolicy,
                    rule: "workspace_rule",
                    reason: matched.reason
                )
            }
        }

        // 3. Global policies
        if let matched = matchRule(rules: globalRules, tool: tool) {
            let effectivePolicy = effectivePolicyForRule(matched, riskLevel: tool.riskLevel)
            return PolicyEvaluationResult(
                decision: effectivePolicy,
                rule: "global_rule",
                reason: matched.reason
            )
        }

        // 4. Tool default (lowest priority)
        return PolicyEvaluationResult(
            decision: tool.defaultApprovalPolicy,
            rule: "tool_default",
            reason: "Default policy for \(tool.name): \(tool.defaultApprovalPolicy.rawValue)"
        )
    }

    // MARK: - Session Overrides

    /// Record a session-level override for a tool.
    public func addSessionOverride(tool: String, decision: ApprovalDecision) {
        sessionOverrides[tool] = decision
    }

    /// Remove a session-level override for a tool.
    public func removeSessionOverride(tool: String) {
        sessionOverrides.removeValue(forKey: tool)
    }

    /// Convenience: set always-allow for a tool (optionally scoped to workspace).
    public func setAlwaysAllow(tool: String, workspace: String? = nil) {
        if let workspace = workspace {
            addWorkspaceRule(
                PolicyRule(
                    toolPattern: tool,
                    workspacePath: workspace,
                    policy: .allow,
                    reason: "Always allow \(tool) in \(workspace)"
                ),
                workspace: workspace
            )
        } else {
            addSessionOverride(tool: tool, decision: .alwaysAllow)
        }
    }

    /// Convenience: set always-deny for a tool (optionally scoped to workspace).
    public func setAlwaysDeny(tool: String, workspace: String? = nil) {
        if let workspace = workspace {
            addWorkspaceRule(
                PolicyRule(
                    toolPattern: tool,
                    workspacePath: workspace,
                    policy: .deny,
                    reason: "Always deny \(tool) in \(workspace)"
                ),
                workspace: workspace
            )
        } else {
            addSessionOverride(tool: tool, decision: .alwaysDeny)
        }
    }

    // MARK: - Workspace Rules

    /// Add a rule scoped to a specific workspace.
    public func addWorkspaceRule(_ rule: PolicyRule, workspace: String) {
        workspaceRules[workspace, default: []].append(rule)
    }

    // MARK: - Global Rules

    /// Add a global policy rule.
    public func addGlobalRule(_ rule: PolicyRule) {
        globalRules.append(rule)
    }

    /// Remove all global rules.
    public func clearGlobalRules() {
        globalRules = []
    }

    /// Remove all workspace rules for a given workspace.
    public func clearWorkspaceRules(workspace: String) {
        workspaceRules.removeValue(forKey: workspace)
    }

    /// Remove all rules and overrides.
    public func reset() {
        sessionOverrides = [:]
        workspaceRules = [:]
        globalRules = []
    }

    // MARK: - RuntimeEvent Helpers

    /// Create a RuntimeEvent for a policy evaluation.
    public static func makePolicyEvaluatedEvent(
        toolName: String,
        result: PolicyEvaluationResult,
        runtime: RuntimeIdentifier,
        sessionID: String? = nil,
        runID: String? = nil
    ) -> RuntimeEvent {
        RuntimeEvent(
            sessionID: sessionID,
            runID: runID,
            runtime: runtime,
            type: .approvalRequested,
            payload: .generic(
                method: "policy.evaluated",
                params: [
                    "tool": toolName,
                    "decision": result.decision.rawValue,
                    "rule": result.rule,
                    "reason": result.reason,
                ]
            )
        )
    }

    /// Create a RuntimeEvent for an approval request (when policy says "ask").
    public static func makeApprovalRequestedEvent(
        requestID: Int,
        toolName: String,
        riskLevel: RiskLevel,
        runtime: RuntimeIdentifier,
        sessionID: String? = nil,
        runID: String? = nil
    ) -> RuntimeEvent {
        RuntimeEvent(
            sessionID: sessionID,
            runID: runID,
            runtime: runtime,
            type: .approvalRequested,
            payload: .approvalRequested(
                requestID: requestID,
                tool: toolName,
                command: nil,
                riskLevel: riskLevel.rawValue
            )
        )
    }

    /// Create a RuntimeEvent for an approval resolution.
    public static func makeApprovalResolvedEvent(
        requestID: Int,
        decision: ApprovalDecision,
        runtime: RuntimeIdentifier,
        sessionID: String? = nil,
        runID: String? = nil
    ) -> RuntimeEvent {
        RuntimeEvent(
            sessionID: sessionID,
            runID: runID,
            runtime: runtime,
            type: .approvalResolved,
            payload: .approvalResolved(
                requestID: requestID,
                decision: decision.rawValue
            )
        )
    }

    // MARK: - Private Helpers

    /// Find the first matching rule in a list for the given tool.
    private func matchRule(rules: [PolicyRule], tool: ToolDefinition) -> PolicyRule? {
        for rule in rules {
            let patternMatches = matchesPattern(rule.toolPattern, toolName: tool.name)
            let riskMatches = rule.riskLevel == nil || rule.riskLevel == tool.riskLevel
            if patternMatches && riskMatches {
                return rule
            }
        }
        return nil
    }

    /// Check if a tool name matches a pattern (exact or glob with `*`).
    private func matchesPattern(_ pattern: String, toolName: String) -> Bool {
        if pattern == toolName { return true }
        if pattern == "*" { return true }

        // Simple glob: "write_*" matches "write_file", "write_anything"
        if pattern.hasSuffix("*") {
            let prefix = String(pattern.dropLast())
            return toolName.hasPrefix(prefix)
        }
        if pattern.hasPrefix("*") {
            let suffix = String(pattern.dropFirst())
            return toolName.hasSuffix(suffix)
        }

        return false
    }

    /// Apply the critical-tool safety guard to a session override.
    ///
    /// Critical tools can NEVER be auto-allowed -- always downgrade to `.ask`.
    private func effectivePolicyForOverride(_ decision: ApprovalDecision, riskLevel: RiskLevel) -> ApprovalPolicy {
        switch decision {
        case .allowOnce:
            return riskLevel == .critical ? .ask : .allow
        case .alwaysAllow:
            return riskLevel == .critical ? .ask : .allow
        case .reject:
            return .deny
        case .alwaysDeny:
            return .deny
        }
    }

    /// Apply the critical-tool safety guard to a matched rule.
    private func effectivePolicyForRule(_ rule: PolicyRule, riskLevel: RiskLevel) -> ApprovalPolicy {
        if riskLevel == .critical && rule.policy == .allow {
            return .ask
        }
        return rule.policy
    }
}
