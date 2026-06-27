import Foundation

@MainActor
public protocol MacRelayRuntimeBridge: AnyObject {
    func enqueueDraft(
        cwd: String,
        text: String,
        model: String?,
        effort: String?,
        threadSandbox: String,
        turnSandbox: String,
        approvalPolicy: String
    ) throws

    func updateSettings(
        model: String?,
        effort: String?,
        approvalPolicy: String?,
        sandboxPolicy: String?
    ) throws -> Int

    func resolveApproval(requestID: Int, decision: String) throws

    /// Return all sessions (threads) known to this runtime.
    func listSessions() -> [RelaySessionInfoPayload]

    /// Stop the current session / thread.
    func stopSession() throws

    /// Select (switch to) the named session. Stops the current
    /// session and initialises a fresh thread in that session's
    /// project context (cwd / model / effort).
    func selectSession(sessionID: String) throws

    /// Return the selected session's cwd, or nil if none selected.
    var selectedSessionCWD: String? { get }

    /// Clear thread state so the next enqueueDraft creates a fresh thread
    /// instead of starting a turn on the existing one.
    func clearCurrentThread()
}

public enum MacRelayRuntimeCommandDispatchResult: Equatable {
    case dispatched(String)
    case unsupported(String)
}

extension MacRelayRuntimeCommandDispatchResult: CustomStringConvertible {
    public var description: String {
        switch self {
        case .dispatched(let detail): return "dispatched: \(detail)"
        case .unsupported(let detail): return "unsupported: \(detail)"
        }
    }
}

@MainActor
public struct MacRelayRuntimeCommandDispatcher {
    private let runtime: MacRelayRuntimeBridge
    private let defaultCWD: () -> String

    public init(runtime: MacRelayRuntimeBridge, defaultCWD: @escaping () -> String) {
        self.runtime = runtime
        self.defaultCWD = defaultCWD
    }

    /// Prefer the selected session's cwd when one is active.
    private var effectiveCWD: String {
        runtime.selectedSessionCWD ?? defaultCWD()
    }

    /// Expose the runtime's session list for WebSocket response encoding.
    public func listSessions() -> [RelaySessionInfoPayload] {
        runtime.listSessions()
    }

    @discardableResult
    public func dispatch(commandType: RelayCommandType, payloadData: Data) throws -> MacRelayRuntimeCommandDispatchResult {
        let decoder = JSONDecoder()
        switch commandType {
        case .sessionStart:
            let payload = try decoder.decode(RelaySessionStartCommandPayload.self, from: payloadData)
            if let initialPrompt = payload.initialPrompt, !initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try runtime.enqueueDraft(
                    cwd: payload.cwd,
                    text: initialPrompt,
                    model: payload.model,
                    effort: payload.effort,
                    threadSandbox: threadSandbox(forPermissionMode: payload.permissionMode, explicitSandbox: payload.sandboxMode),
                    turnSandbox: turnSandbox(forPermissionMode: payload.permissionMode, explicitSandbox: payload.sandboxMode),
                    approvalPolicy: payload.approvalPolicy ?? approvalPolicy(forPermissionMode: payload.permissionMode)
                )
                return .dispatched("session.start with prompt")
            }
            // No initialPrompt: create a fresh thread (not a turn on the
            // existing one). Clear currentThread first so enqueueDraft's
            // else-if chain reaches startThread(draft:) instead of
            // startTurnFromDraft.
            runtime.clearCurrentThread()
            try runtime.enqueueDraft(
                cwd: payload.cwd,
                text: "",
                model: payload.model,
                effort: payload.effort,
                threadSandbox: threadSandbox(forPermissionMode: payload.permissionMode, explicitSandbox: payload.sandboxMode),
                turnSandbox: turnSandbox(forPermissionMode: payload.permissionMode, explicitSandbox: payload.sandboxMode),
                approvalPolicy: payload.approvalPolicy ?? approvalPolicy(forPermissionMode: payload.permissionMode)
            )
            return .dispatched("session.start ready")

        case .turnStart:
            let payload = try decoder.decode(RelayTurnStartCommandPayload.self, from: payloadData)
            let permissionMode = payload.permissionMode ?? "Default"
            try runtime.enqueueDraft(
                cwd: effectiveCWD,
                text: payload.input,
                model: payload.model,
                effort: payload.effort,
                threadSandbox: threadSandbox(forPermissionMode: permissionMode, explicitSandbox: nil),
                turnSandbox: turnSandbox(forPermissionMode: permissionMode, explicitSandbox: nil),
                approvalPolicy: approvalPolicy(forPermissionMode: permissionMode)
            )
            return .dispatched("session.turn.start")

        case .settingsUpdate:
            let payload = try decoder.decode(RelaySettingsUpdateCommandPayload.self, from: payloadData)
            let sandbox = payload.sandboxMode ?? payload.permissionMode.map { turnSandbox(forPermissionMode: $0, explicitSandbox: nil) }
            _ = try runtime.updateSettings(
                model: payload.model,
                effort: payload.effort,
                approvalPolicy: payload.approvalPolicy ?? payload.permissionMode.map(approvalPolicy(forPermissionMode:)),
                sandboxPolicy: sandbox
            )
            return .dispatched("session.settings.update")

        case .approvalResolve:
            let payload = try decoder.decode(RelayApprovalResolveCommandPayload.self, from: payloadData)
            try runtime.resolveApproval(requestID: payload.requestID, decision: payload.decision)
            return .dispatched("approval.resolve")

        case .sessionList:
            let sessions = runtime.listSessions()
            return .dispatched("session.list count=\(sessions.count)")

        case .sessionSelect:
            let payload = try decoder.decode(RelaySessionSelectCommandPayload.self, from: payloadData)
            try runtime.selectSession(sessionID: payload.sessionID)
            return .dispatched("session.select sessionID=\(payload.sessionID)")

        case .sessionStop:
            try runtime.stopSession()
            return .dispatched("session.stop")

        default:
            return .unsupported("\(commandType.rawValue) not routed to CodexRuntimeBridge")
        }
    }

    public func threadSandbox(forPermissionMode permissionMode: String, explicitSandbox: String?) -> String {
        if let explicitSandbox { return explicitSandbox }
        switch permissionMode {
        case "Full Access", "fullAccess", "full-access": return "danger-full-access"
        case "Read Only", "readOnly", "read-only": return "read-only"
        default: return "workspace-write"
        }
    }

    public func turnSandbox(forPermissionMode permissionMode: String, explicitSandbox: String?) -> String {
        if let explicitSandbox { return explicitSandbox }
        switch permissionMode {
        case "Full Access", "fullAccess", "full-access": return "dangerFullAccess"
        case "Read Only", "readOnly", "read-only": return "readOnly"
        default: return "workspaceWrite"
        }
    }

    public func approvalPolicy(forPermissionMode permissionMode: String) -> String {
        switch permissionMode {
        case "Full Access", "fullAccess", "full-access": return "never"
        default: return "on-request"
        }
    }
}
