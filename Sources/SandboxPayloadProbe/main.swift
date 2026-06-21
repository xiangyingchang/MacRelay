import Foundation

enum PermissionMode: String, CaseIterable {
    case readOnly = "Read Only"
    case `default` = "Default"
    case fullAccess = "Full Access"

    var threadSandbox: String {
        switch self {
        case .fullAccess: return "danger-full-access"
        case .default: return "workspace-write"
        case .readOnly: return "read-only"
        }
    }

    var turnSandbox: String {
        switch self {
        case .fullAccess: return "dangerFullAccess"
        case .default: return "workspaceWrite"
        case .readOnly: return "readOnly"
        }
    }

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

func makeThreadStartParams(
    cwd: String,
    model: String?,
    effort: String?,
    sandbox: String,
    approvalPolicy: String
) -> [String: Any] {
    var params: [String: Any] = [
        "cwd": cwd,
        "sandbox": sandbox,
        "approvalPolicy": approvalPolicy,
        "sessionStartSource": "startup"
    ]
    if let model { params["model"] = model }
    if let effort { params["effort"] = effort }
    return params
}

func makeTurnStartParams(
    threadID: String,
    text: String,
    model: String?,
    effort: String?,
    approvalPolicy: String?,
    sandboxPolicy: String?
) -> [String: Any] {
    var params: [String: Any] = [
        "threadId": threadID,
        "input": [["type": "text", "text": text]]
    ]
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

let threadAllowed = Set(["read-only", "workspace-write", "danger-full-access"])
let turnAllowed = Set(["readOnly", "workspaceWrite", "dangerFullAccess"])
let cwd = "/private/tmp/AgentClientM1Prototype"

do {
    for mode in PermissionMode.allCases {
        let threadParams = makeThreadStartParams(
            cwd: cwd,
            model: "gpt-5.5",
            effort: "low",
            sandbox: mode.threadSandbox,
            approvalPolicy: mode.approvalPolicy
        )
        let turnParams = makeTurnStartParams(
            threadID: "thread-1",
            text: "hello",
            model: "gpt-5.5",
            effort: "low",
            approvalPolicy: mode.approvalPolicy,
            sandboxPolicy: mode.turnSandbox
        )

        let threadSandbox = threadParams["sandbox"] as? String
        let turnSandbox = (turnParams["sandboxPolicy"] as? [String: Any])?["type"] as? String

        try require(threadSandbox == mode.threadSandbox, "\(mode.rawValue): thread/start sandbox changed during payload construction")
        try require(turnSandbox == mode.turnSandbox, "\(mode.rawValue): turn/start sandboxPolicy changed during payload construction")
        try require(threadAllowed.contains(threadSandbox ?? ""), "\(mode.rawValue): thread/start sandbox is not kebab-case: \(threadSandbox ?? "nil")")
        try require(turnAllowed.contains(turnSandbox ?? ""), "\(mode.rawValue): turn/start sandboxPolicy.type is not camelCase: \(turnSandbox ?? "nil")")

        let threadData = try JSONSerialization.data(withJSONObject: threadParams, options: [.sortedKeys])
        let turnData = try JSONSerialization.data(withJSONObject: turnParams, options: [.sortedKeys])
        try require(String(data: threadData, encoding: .utf8)?.contains("\"sandbox\":\"\(mode.threadSandbox)\"") == true, "\(mode.rawValue): serialized thread/start sandbox mismatch")
        try require(String(data: turnData, encoding: .utf8)?.contains("\"type\":\"\(mode.turnSandbox)\"") == true, "\(mode.rawValue): serialized turn/start sandbox mismatch")
    }

    print("SandboxPayloadProbe passed")
} catch {
    fputs("SandboxPayloadProbe failed: \(error)\n", stderr)
    exit(1)
}
