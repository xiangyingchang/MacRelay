import Foundation

// MARK: - Provider type

public enum AgentProvider: String, Codable, CaseIterable {
    case codex = "Codex CLI"
    case claudeCode = "Claude Code"
}

// MARK: - AgentRuntime

/// Base class for AI coding CLI runtimes (Codex CLI / Claude Code).
/// Both speak JSON-RPC 2.0 over stdio with compatible event shapes.
/// Using a class (not a protocol) so `ObservableObject` conformance
/// is inherited and `@Published` properties work with SwiftUI.
@MainActor
open class AgentRuntime: ObservableObject {
    @Published open var statusText = ""
    @Published open var modelNames: [String] = []
    @Published open var currentThreadID: String?
    @Published open var snapshot = SessionSnapshot()
    @Published open var latestTurnID: String?
    @Published open var isAppServerRunning = false
    @Published open var isInitialized = false
    @Published open var isInitializing = false
    @Published open var rateLimitText = ""
    @Published open var currentSteps: [TurnStep] = []
    open var isReadyForAppServer: Bool { false }

    open func refreshDetection() {}
    open var cliInstalled: Bool { false }

    open func startAppServer(cwd: String) throws { fatalError("abstract") }
    open func stopAppServer() {}
    @discardableResult
    open func initialize() throws -> Int { fatalError("abstract") }
    @Published open var sessions: [RelaySessionInfoPayload] = []
    @Published open var selectedSessionID: String?

    open var selectedSessionCWD: String? { nil }

    open var onEventReceived: ((CodexAppServerEvent) -> Void)?
    open var onThreadStarted: ((String) -> Void)?

    public init() {}

    open func resetSteps() { currentSteps = [] }

    open func addStep(_ kind: TurnStepKind, detail: String? = nil, status: StepStatus = .completed) {
        currentSteps.append(TurnStep(kind: kind, detail: detail, status: status))
    }

    open func updateLastStep(status: StepStatus) {
        guard !currentSteps.isEmpty else { return }
        currentSteps[currentSteps.count - 1].status = status
    }

    /// Mark all `.active` steps as `.completed`.
    open func completeActiveSteps() {
        var steps = currentSteps
        var changed = false
        for i in steps.indices where steps[i].status == .active {
            steps[i].status = .completed
            changed = true
        }
        if changed { currentSteps = steps }
    }

    open func enqueueDraft(
        cwd: String, text: String, model: String?, effort: String?,
        threadSandbox: String, turnSandbox: String, approvalPolicy: String
    ) throws { fatalError("abstract") }

    @discardableResult
    open func updateSettings(
        model: String?, effort: String?, approvalPolicy: String?,
        sandboxPolicy: String?
    ) throws -> Int { fatalError("abstract") }

    open func resolveApproval(requestID: Int, decision: String) throws { fatalError("abstract") }
    open func listSessions() -> [RelaySessionInfoPayload] { [] }
    open func rememberSession(sessionID: String, cwd: String?, title: String?, status: String?) {}
    open func stopSession() throws {}
    open func selectSession(sessionID: String) throws {}
    open func clearCurrentThread() {}
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
    private let runtime: AgentRuntime
    private let defaultCWD: () -> String

    public init(runtime: AgentRuntime, defaultCWD: @escaping () -> String) {
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
