import Foundation

// MARK: - Permission Mode Mappings (mirrors MacShellViewModel)
// These mappings are shared with thread/start, turn/start, and settings/update.
// Changes here must be kept in sync with MacShellViewModel in Models.swift.

enum PermissionMode: String, CaseIterable {
    case readOnly = "Read Only"
    case `default` = "Default"
    case fullAccess = "Full Access"

    /// kebab-case for thread/start "sandbox"
    var threadSandbox: String {
        switch self {
        case .fullAccess: return "danger-full-access"
        case .default: return "workspace-write"
        case .readOnly: return "read-only"
        }
    }

    /// camelCase for turn/start "sandboxPolicy.type" and thread/settings/update "sandboxPolicy.type"
    /// App-server 0.141.0 uses camelCase for sandboxPolicy.type in settings contexts.
    var turnSandbox: String {
        switch self {
        case .fullAccess: return "dangerFullAccess"
        case .default: return "workspaceWrite"
        case .readOnly: return "readOnly"
        }
    }

    /// App-server approval policy per permission mode.
    var approvalPolicy: String {
        switch self {
        case .fullAccess: return "never"
        case .default, .readOnly: return "on-request"
        }
    }
}

struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
}

// MARK: - Payload Builder (mirrors CodexRuntimeBridge.updateSettings)

/// Constructs the params dictionary for a thread/settings/update request.
/// Matches the schema expected by app-server 0.141.0+.
/// - Parameters are all optional; only non-nil values are included.
/// - sandboxPolicy is wrapped as `["type": value]` to match the server's object schema.
func makeSettingsUpdateParams(
    threadID: String,
    model: String?,
    effort: String?,
    approvalPolicy: String?,
    sandboxPolicy: String?
) -> [String: Any] {
    var params: [String: Any] = ["threadId": threadID]
    if let model { params["model"] = model }
    if let effort { params["effort"] = effort }
    if let approvalPolicy { params["approvalPolicy"] = approvalPolicy }
    if let sandboxPolicy { params["sandboxPolicy"] = ["type": sandboxPolicy] }
    return params
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw ProbeFailure(description: message)
    }
}

// MARK: - Validation

/// Allowed camelCase values for sandboxPolicy.type in thread/settings/update.
let allowedSandboxTypes = Set(["readOnly", "workspaceWrite", "dangerFullAccess"])

/// Allowed approval policy values.
let allowedApprovalPolicies = Set(["on-request", "never", "always"])

let cwd = "/private/tmp/AgentClientM1Prototype"

do {
    for mode in PermissionMode.allCases {
        // --- Full payload (all fields set) ---
        let fullParams = makeSettingsUpdateParams(
            threadID: "thread-1",
            model: "gpt-5.5",
            effort: "low",
            approvalPolicy: mode.approvalPolicy,
            sandboxPolicy: mode.turnSandbox
        )
        let sandboxPolicy = fullParams["sandboxPolicy"] as? [String: Any]
        let sandboxType = sandboxPolicy?["type"] as? String

        try require(fullParams["model"] as? String == "gpt-5.5",
                     "\(mode.rawValue): model passthrough failed")
        try require(fullParams["threadId"] as? String == "thread-1",
                     "\(mode.rawValue): threadId passthrough failed")
        try require(fullParams["effort"] as? String == "low",
                     "\(mode.rawValue): effort passthrough failed")
        try require(fullParams["approvalPolicy"] as? String == mode.approvalPolicy,
                     "\(mode.rawValue): approvalPolicy mapping failed")
        try require(allowedApprovalPolicies.contains(mode.approvalPolicy),
                     "\(mode.rawValue): approvalPolicy '\(mode.approvalPolicy)' is not recognized")
        try require(sandboxPolicy != nil,
                     "\(mode.rawValue): sandboxPolicy should be a dictionary, got nil")
        try require(sandboxType == mode.turnSandbox,
                     "\(mode.rawValue): sandboxPolicy.type expected '\(mode.turnSandbox)', got '\(sandboxType ?? "nil")'")
        try require(allowedSandboxTypes.contains(sandboxType ?? ""),
                     "\(mode.rawValue): sandboxPolicy.type '\(sandboxType ?? "nil")' is not camelCase")

        // Verify camelCase (no hyphens in sandboxPolicy.type)
        try require(sandboxType?.contains("-") != true,
                     "\(mode.rawValue): sandboxPolicy.type '\(sandboxType ?? "")' contains hyphen (must be camelCase)")

        // --- Minimal payload (only sandboxPolicy) ---
        let minimalParams = makeSettingsUpdateParams(
            threadID: "thread-1",
            model: nil,
            effort: nil,
            approvalPolicy: nil,
            sandboxPolicy: "readOnly"
        )
        try require(minimalParams.keys.count == 2,
                     "minimal: expected 2 keys, got \(minimalParams.keys)")
        try require(minimalParams["sandboxPolicy"] != nil,
                     "minimal: sandboxPolicy should be present")
        try require(minimalParams["model"] == nil,
                     "minimal: model should be nil when not provided")

        // --- Partial payload (model + sandboxPolicy only) ---
        let partialParams = makeSettingsUpdateParams(
            threadID: "thread-1",
            model: "claude-sonnet-4-6",
            effort: nil,
            approvalPolicy: nil,
            sandboxPolicy: "workspaceWrite"
        )
        try require(partialParams.keys.count == 3,
                     "partial: expected 3 keys, got \(partialParams.keys): \(partialParams)")
        try require(partialParams["effort"] == nil,
                     "partial: effort should be nil when not provided")
        try require(partialParams["approvalPolicy"] == nil,
                     "partial: approvalPolicy should be nil when not provided")

        // --- JSON serialization round-trip ---
        let fullData = try JSONSerialization.data(withJSONObject: fullParams, options: [.sortedKeys])
        let serialized = String(data: fullData, encoding: .utf8) ?? ""

        try require(serialized.contains("\"model\":\"gpt-5.5\""),
                     "\(mode.rawValue): serialized payload missing model")
        try require(serialized.contains("\"effort\":\"low\""),
                     "\(mode.rawValue): serialized payload missing effort")
        try require(serialized.contains("\"approvalPolicy\":\"\(mode.approvalPolicy)\""),
                     "\(mode.rawValue): serialized payload missing approvalPolicy")
        try require(serialized.contains("\"type\":\"\(mode.turnSandbox)\""),
                     "\(mode.rawValue): serialized payload missing sandboxPolicy.type")

        print("  [OK] \(mode.rawValue): sandboxType=\(sandboxType ?? "nil") approvalPolicy=\(mode.approvalPolicy)")
    }

    // --- Additional shape validations ---

    // Verify that sandboxPolicy is always a dict with "type", never a raw string
    let rawStringTest = makeSettingsUpdateParams(
        threadID: "thread-1",
        model: nil, effort: nil, approvalPolicy: nil, sandboxPolicy: "readOnly"
    )
    let sp = rawStringTest["sandboxPolicy"]
    try require(sp is [String: Any],
                 "sandboxPolicy must be a dictionary, got \(type(of: sp))")
    try require((sp as? [String: Any])?["type"] as? String == "readOnly",
                 "sandboxPolicy.type value passthrough failed")

    // Verify all three sandbox types are distinct (no collisions)
    let allSandboxTypes = Set(PermissionMode.allCases.map(\.turnSandbox))
    try require(allSandboxTypes.count == 3,
                 "expected 3 distinct sandboxPolicy types, got \(allSandboxTypes)")

    print()
    print("SettingsUpdateSchemaProbe passed")
} catch {
    fputs("SettingsUpdateSchemaProbe failed: \(error)\n", stderr)
    exit(1)
}
