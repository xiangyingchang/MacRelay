import Foundation

// MARK: - Risk Level

/// Risk level for tool execution, used to determine approval requirements.
public enum RiskLevel: String, Codable, Equatable, Comparable {
    case low
    case medium
    case high
    case critical

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
}

// MARK: - Approval Policy

/// Policy for tool execution approval.
public enum ApprovalPolicy: String, Codable, Equatable {
    /// Execute without asking the user.
    case allow
    /// Ask the user for approval before execution.
    case ask
    /// Block execution entirely.
    case deny
}

// MARK: - Tool Definition

/// Describes a tool that can be registered in the ToolRegistry.
///
/// Unlike `OpenAIToolDefinition` (wire format for OpenAI API), this is the
/// canonical definition used for tool discovery, approval decisions, and
/// capability tracking.
public struct ToolDefinition: Codable, Identifiable, Equatable {
    /// Unique tool identifier (matches the tool name).
    public let id: String
    /// Tool name used in tool calls.
    public let name: String
    /// Human-readable display name.
    public let displayName: String
    /// Description of what the tool does.
    public let description: String
    /// JSON Schema for tool input parameters.
    public let inputSchema: [String: AnyCodable]?
    /// JSON Schema for tool output.
    public let outputSchema: [String: AnyCodable]?
    /// Risk level of this tool.
    public let riskLevel: RiskLevel
    /// Default approval policy for this tool.
    public let defaultApprovalPolicy: ApprovalPolicy
    /// Capability tags (e.g. ["read", "write", "execute"]).
    public let capabilities: [String]

    public init(
        name: String,
        displayName: String,
        description: String,
        inputSchema: [String: AnyCodable]? = nil,
        outputSchema: [String: AnyCodable]? = nil,
        riskLevel: RiskLevel,
        defaultApprovalPolicy: ApprovalPolicy,
        capabilities: [String]
    ) {
        self.id = name
        self.name = name
        self.displayName = displayName
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.riskLevel = riskLevel
        self.defaultApprovalPolicy = defaultApprovalPolicy
        self.capabilities = capabilities
    }

    // MARK: Equatable

    public static func == (lhs: ToolDefinition, rhs: ToolDefinition) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.displayName == rhs.displayName
            && lhs.description == rhs.description
            && lhs.riskLevel == rhs.riskLevel
            && lhs.defaultApprovalPolicy == rhs.defaultApprovalPolicy
            && lhs.capabilities == rhs.capabilities
    }

    // MARK: Codable — manual for AnyCodable fields

    enum CodingKeys: String, CodingKey {
        case id, name, displayName, description
        case inputSchema, outputSchema
        case riskLevel, defaultApprovalPolicy, capabilities
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        displayName = try c.decode(String.self, forKey: .displayName)
        description = try c.decode(String.self, forKey: .description)
        inputSchema = try c.decodeIfPresent([String: AnyCodable].self, forKey: .inputSchema)
        outputSchema = try c.decodeIfPresent([String: AnyCodable].self, forKey: .outputSchema)
        riskLevel = try c.decode(RiskLevel.self, forKey: .riskLevel)
        defaultApprovalPolicy = try c.decode(ApprovalPolicy.self, forKey: .defaultApprovalPolicy)
        capabilities = try c.decode([String].self, forKey: .capabilities)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(description, forKey: .description)
        try c.encodeIfPresent(inputSchema, forKey: .inputSchema)
        try c.encodeIfPresent(outputSchema, forKey: .outputSchema)
        try c.encode(riskLevel, forKey: .riskLevel)
        try c.encode(defaultApprovalPolicy, forKey: .defaultApprovalPolicy)
        try c.encode(capabilities, forKey: .capabilities)
    }
}

// MARK: - Tool Call (Registry)

/// A tool call submitted for execution through the ToolRegistry.
public struct ToolCall: Codable, Equatable {
    /// Unique identifier for this tool call (from the LLM).
    public let id: String
    /// Name of the tool to call.
    public let name: String
    /// Parameters for the tool call as string values.
    public let parameters: [String: String]

    public init(id: String, name: String, parameters: [String: String]) {
        self.id = id
        self.name = name
        self.parameters = parameters
    }
}

// MARK: - Tool Result

/// The result of executing a tool through the ToolRegistry.
public struct ToolResult: Codable, Equatable {
    /// The ID of the tool call this result corresponds to.
    public let callID: String
    /// Whether the execution succeeded.
    public let success: Bool
    /// Output from the tool (present on success).
    public let output: String?
    /// Error message (present on failure).
    public let error: String?

    public init(callID: String, success: Bool, output: String? = nil, error: String? = nil) {
        self.callID = callID
        self.success = success
        self.output = output
        self.error = error
    }
}

// MARK: - Tool Execution Context

/// Context provided to a ToolExecutor during execution.
public struct ToolExecutionContext {
    /// The workspace path for the current session.
    public let workspacePath: String
    /// The current session ID (if any).
    public let sessionID: String?
    /// The current run ID (if any).
    public let runID: String?

    public init(workspacePath: String, sessionID: String? = nil, runID: String? = nil) {
        self.workspacePath = workspacePath
        self.sessionID = sessionID
        self.runID = runID
    }
}
