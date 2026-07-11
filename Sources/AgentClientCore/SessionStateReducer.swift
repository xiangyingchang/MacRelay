import Foundation

public struct SessionSnapshot {
    public var threadID: String?
    public var cwd: String?
    public var status: SessionStatus = .idle
    public var settings: SessionSettingsSnapshot?
    public var activeTurn: TurnSnapshot?
    public var completedTurns: [TurnSnapshot] = []
    public var availableModels: [String]?
    public var pendingApprovals: [String: ApprovalSnapshot] = [:]
    public var fileChanges: [String: FileChangeSnapshot] = [:]
    public var turnDiff: CodexTurnDiffUpdated?
    public var lastError: SessionErrorSnapshot?
    public var rateLimit: RateLimitSnapshot?
    public var hasExited = false

    // MARK: - Run Tracking

    /// The currently active run (one task execution).
    public var activeRun: AgentRun?

    /// Completed runs history.
    public var completedRuns: [AgentRun] = []

    public init() {}
}

public enum SessionStatus: String {
    case idle
    case active
    case waitingOnApproval
    case systemError
    case completed
    case failed
    case exited
}

public struct SessionSettingsSnapshot {
    public var model: String?
    public var effort: String?
    public var provider: String?
    public var approvalPolicy: String?
    public var sandboxType: String?
    public var cwd: String?

    public init(
        model: String? = nil,
        effort: String? = nil,
        provider: String? = nil,
        approvalPolicy: String? = nil,
        sandboxType: String? = nil,
        cwd: String? = nil
    ) {
        self.model = model
        self.effort = effort
        self.provider = provider
        self.approvalPolicy = approvalPolicy
        self.sandboxType = sandboxType
        self.cwd = cwd
    }
}

public struct TurnSnapshot {
    public var id: String?
    public var userMessage: String?
    public var assistantText = ""
    public var isCompleted = false
}

public struct ApprovalSnapshot {
    public var requestID: Int
    public var method: String
    public var title: String
    public var reason: String?
    public var command: String?
    public var decision: String?
    public var isPending: Bool
}

public struct FileChangeSnapshot {
    public var id: String
    public var path: String?
    public var changeKind: String?
    public var diffLength: Int
}

public struct SessionErrorSnapshot {
    public var message: String
    public var code: String?
    public var willRetry: Bool?
}

public struct RateLimitSnapshot {
    public var planType: String?
    public var limitID: String?
    public var rateLimitReachedType: String?

    public static func format(params: [String: Any]?) -> String {
        guard let rateLimits = params?["rateLimits"] as? [String: Any] else { return "" }

        let plan = rateLimits["planType"] as? String ?? "unknown"
        let primary = rateLimits["primary"] as? [String: Any] ?? [:]
        let secondary = rateLimits["secondary"] as? [String: Any] ?? [:]
        let usedPercent: String
        if let pct = primary["usedPercent"] as? Double {
            usedPercent = String(format: "%.0f%%", pct * 100)
        } else if let pct = primary["usedPercent"] as? Int {
            usedPercent = "\(pct)%"
        } else if let pct = primary["usedPercent"] as? NSNumber {
            usedPercent = String(format: "%.0f%%", pct.doubleValue * 100)
        } else {
            usedPercent = "?"
        }
        let window = primary["windowDurationMins"] ?? "?"
        let resetsAt = primary["resetsAt"] ?? secondary["resetsAt"] ?? "?"

        return "Plan: \(plan) | Used: \(usedPercent) | Window: \(window)m | Reset: \(resetsAt)"
    }
}

public enum SessionReducerAction {
    case threadStarted(params: [String: Any])
    case statusChanged(params: [String: Any])
    case settingsUpdated(params: [String: Any])
    case turnStarted(params: [String: Any])
    case assistantDelta(String)
    case turnCompleted(params: [String: Any])
    case approvalRequested(CodexApprovalRequest)
    case approvalResolved(requestID: Int, decision: String)
    case diffUpdated(CodexTurnDiffUpdated)
    case fileChangeUpdated(CodexFileChangeUpdated)
    case error(params: [String: Any])
    case rateLimitsUpdated(params: [String: Any])
    case modelListResult(models: [String])
    case exited(code: Int32)

    // MARK: - Run Lifecycle

    case runStarted(runID: String, input: String?, runtime: RuntimeIdentifier)
    case runWaitingApproval(runID: String)
    case runResumed(runID: String)
    case runCompleted(runID: String, summary: String?)
    case runFailed(runID: String, error: String?)
    case runCancelled(runID: String)
}

public struct SessionStateReducer {
    public init() {}

    public func reduce(_ state: inout SessionSnapshot, action: SessionReducerAction) {
        switch action {
        case let .threadStarted(params):
            let thread = params["thread"] as? [String: Any]
            state.threadID = thread?["id"] as? String ?? params["id"] as? String ?? state.threadID
            state.cwd = thread?["cwd"] as? String ?? params["cwd"] as? String ?? state.cwd
            let status = thread?["status"] as? [String: Any] ?? params["status"] as? [String: Any]
            state.status = SessionStatus(rawValue: status?["type"] as? String ?? "") ?? .idle
            // New thread → clear conversation history from the previous session
            state.activeTurn = nil
            state.completedTurns = []
            state.pendingApprovals = [:]
            state.fileChanges = [:]
            state.turnDiff = nil
            state.lastError = nil
            state.hasExited = false

        case let .statusChanged(params):
            let status = params["status"] as? [String: Any]
            let type = status?["type"] as? String
            let flags = status?["activeFlags"] as? [String] ?? []
            if flags.contains("waitingOnApproval") {
                state.status = .waitingOnApproval
            } else {
                state.status = SessionStatus(rawValue: type ?? "") ?? state.status
            }

        case let .settingsUpdated(params):
            let settings = params["threadSettings"] as? [String: Any] ?? params["settings"] as? [String: Any] ?? [:]
            let sandbox = settings["sandboxPolicy"] as? [String: Any]
            state.settings = SessionSettingsSnapshot(
                model: settings["model"] as? String,
                effort: settings["effort"] as? String,
                approvalPolicy: settings["approvalPolicy"] as? String,
                sandboxType: sandbox?["type"] as? String,
                cwd: settings["cwd"] as? String
            )
            state.cwd = state.settings?.cwd ?? state.cwd

        case let .turnStarted(params):
            let turn = params["turn"] as? [String: Any]
            // Try multiple paths for the turn ID: some app-servers send
            // it nested (turn.id), others at top level (id, turn_id).
            let newId = turn?["id"] as? String
                ?? params["id"] as? String
                ?? params["turn_id"] as? String
            // Archive previous turn if different
            if let active = state.activeTurn, let activeId = active.id, activeId != newId, !active.isCompleted {
                state.completedTurns.append(active)
            }
            state.activeTurn = TurnSnapshot(
                id: newId,
                userMessage: params["input"] as? String ?? params["userMessage"] as? String,
                assistantText: "",
                isCompleted: false
            )
            state.status = .active

        case let .assistantDelta(delta):
            if state.activeTurn == nil {
                state.activeTurn = TurnSnapshot()
            }
            state.activeTurn?.assistantText += delta

        case .turnCompleted:
            if let active = state.activeTurn {
                var completed = active
                completed.isCompleted = true
                state.completedTurns.append(completed)
                state.activeTurn = completed
            }
            state.status = state.lastError == nil ? .completed : .failed

        case let .approvalRequested(request):
            state.pendingApprovals[String(request.requestID)] = ApprovalSnapshot(
                requestID: request.requestID,
                method: request.method,
                title: request.method,
                reason: request.reason,
                command: request.command.map { String(describing: $0) },
                decision: nil,
                isPending: true
            )
            state.status = .waitingOnApproval

        case let .approvalResolved(requestID, decision):
            let key = String(requestID)
            guard var approval = state.pendingApprovals[key] else {
                return
            }
            approval.decision = decision
            approval.isPending = false
            state.pendingApprovals[key] = approval
            if state.status == .waitingOnApproval {
                state.status = .active
            }

        case let .diffUpdated(diff):
            state.turnDiff = diff

        case let .fileChangeUpdated(change):
            let id = change.itemID ?? change.path ?? UUID().uuidString
            state.fileChanges[id] = FileChangeSnapshot(
                id: id,
                path: change.path,
                changeKind: change.changeKind,
                diffLength: change.diff?.count ?? 0
            )

        case let .error(params):
            let error = params["error"] as? [String: Any] ?? [:]
            state.lastError = SessionErrorSnapshot(
                message: error["message"] as? String ?? "Unknown error",
                code: error["codexErrorInfo"] as? String,
                willRetry: params["willRetry"] as? Bool
            )
            state.status = .systemError

        case let .rateLimitsUpdated(params):
            let rateLimits = params["rateLimits"] as? [String: Any] ?? [:]
            state.rateLimit = RateLimitSnapshot(
                planType: rateLimits["planType"] as? String,
                limitID: rateLimits["limitId"] as? String,
                rateLimitReachedType: rateLimits["rateLimitReachedType"] as? String
            )

        case let .modelListResult(models):
            state.availableModels = models

        case .exited:
            state.hasExited = true
            state.status = .exited

        // MARK: - Run Lifecycle

        case let .runStarted(runID, input, runtime):
            let run = AgentRun(
                id: runID,
                sessionID: state.threadID ?? "",
                runtime: runtime,
                status: .running,
                input: input
            )
            state.activeRun = run

        case let .runWaitingApproval(runID):
            guard state.activeRun?.id == runID else { return }
            state.activeRun?.waitForApproval()

        case let .runResumed(runID):
            guard state.activeRun?.id == runID else { return }
            state.activeRun?.resume()

        case let .runCompleted(runID, summary):
            guard state.activeRun?.id == runID else { return }
            state.activeRun?.complete(summary: summary)
            if let run = state.activeRun {
                state.completedRuns.append(run)
            }
            state.activeRun = nil

        case let .runFailed(runID, error):
            guard state.activeRun?.id == runID else { return }
            state.activeRun?.fail(error: error)
            if let run = state.activeRun {
                state.completedRuns.append(run)
            }
            state.activeRun = nil

        case let .runCancelled(runID):
            guard state.activeRun?.id == runID else { return }
            state.activeRun?.cancel()
            if let run = state.activeRun {
                state.completedRuns.append(run)
            }
            state.activeRun = nil
        }
    }

    // MARK: - RuntimeEvent → Actions (Primary Path)

    /// Convert a RuntimeEvent into reducer actions.
    /// This is the primary entry point — the reducer only depends on RuntimeEvent,
    /// not on any runtime-specific protocol (Codex JSON-RPC, Claude events, etc.).
    public func actions(from event: RuntimeEvent) -> [SessionReducerAction] {
        switch event.type {
        case .sessionStarted:
            if case let .sessionStarted(sid, cwd) = event.payload {
                var params: [String: Any] = ["id": sid]
                if let cwd { params["cwd"] = cwd }
                return [.threadStarted(params: params)]
            }
            return [.threadStarted(params: [:])]

        case .sessionStopped, .sessionSelected:
            return [] // No snapshot impact

        case .turnStarted:
            if case let .turnStarted(turnID, input) = event.payload {
                var params: [String: Any] = [:]
                if let turnID { params["turn_id"] = turnID }
                if let input { params["input"] = input }
                return [.turnStarted(params: params)]
            }
            return [.turnStarted(params: [:])]

        case .turnCompleted:
            return [.turnCompleted(params: [:])]

        case .turnError:
            if case let .turnError(_, message) = event.payload {
                return [.error(params: ["error": ["message": message]])]
            }
            return [.error(params: [:])]

        case .assistantDelta:
            if case let .assistantDelta(text) = event.payload {
                return [.assistantDelta(text)]
            }
            return []

        case .assistantMessageCompleted:
            return [] // Snapshot already updated by preceding deltas

        case .toolCallRequested, .toolCallCompleted, .toolCallFailed:
            return [] // Timeline-only; no snapshot mutation

        case .approvalRequested:
            if case let .approvalRequested(requestID, tool, command, _) = event.payload {
                // Build a minimal CodexApprovalRequest for the existing reduce() path.
                // The method must contain "requestApproval" for CodexApprovalRequest init to succeed.
                let method = "requestApproval_\(tool)"
                var params: [String: Any] = [:]
                if let command { params["command"] = command }
                if let approval = CodexApprovalRequest(requestID: requestID, method: method, params: params) {
                    return [.approvalRequested(approval)]
                }
            }
            return []

        case .approvalResolved:
            if case let .approvalResolved(requestID, decision) = event.payload {
                return [.approvalResolved(requestID: requestID, decision: decision)]
            }
            return []

        case .fileChangeDetected:
            if case let .fileChange(path, changeKind) = event.payload {
                return [.fileChangeUpdated(CodexFileChangeUpdated(
                    path: path, changeKind: changeKind
                ))]
            }
            return []

        case .diffUpdated:
            if case let .diffUpdated(files) = event.payload {
                return [.diffUpdated(CodexTurnDiffUpdated(changedFiles: files))]
            }
            return []

        case .error:
            if case let .error(message, code) = event.payload {
                var errorDict: [String: Any] = ["message": message]
                if let code { errorDict["code"] = code }
                return [.error(params: ["error": errorDict])]
            }
            return [.error(params: [:])]

        case .exited:
            if case let .exited(code) = event.payload {
                return [.exited(code: code)]
            }
            return [.exited(code: 1)]

        case .settingsUpdated:
            if case let .settingsUpdated(model, effort) = event.payload {
                var settings: [String: Any] = [:]
                if let model { settings["model"] = model }
                if let effort { settings["effort"] = effort }
                return [.settingsUpdated(params: ["threadSettings": settings])]
            }
            return []

        case .unknown:
            return [] // Unknown events have no snapshot impact
        }
    }

    // MARK: - CodexAppServerEvent → Actions (Deprecated Wrapper)

    @available(*, deprecated, message: "Use actions(from: RuntimeEvent) instead. Convert via CodexRuntimeAdapter.")
    public func actions(from event: CodexAppServerEvent) -> [SessionReducerAction] {
        switch event {
        case let .serverRequest(id, method, params):
            if let approval = CodexApprovalRequest(requestID: id, method: method, params: params) {
                return [.approvalRequested(approval)]
            }
            return []

        case let .notification(method, params):
            guard let params else { return [] }
            if let diff = CodexTurnDiffUpdated(method: method, params: params) {
                return [.diffUpdated(diff)]
            }
            if let fileChange = CodexFileChangeUpdated(method: method, params: params) {
                return [.fileChangeUpdated(fileChange)]
            }
            switch method {
            case "thread/started":
                return [.threadStarted(params: params)]
            case "thread/status/changed":
                return [.statusChanged(params: params)]
            case "thread/settings/updated":
                return [.settingsUpdated(params: params)]
            case "turn/started":
                return [.turnStarted(params: params)]
            case "item/agentMessage/delta":
                return [.assistantDelta(params["delta"] as? String ?? "")]
            case "turn/completed":
                return [.turnCompleted(params: params)]
            case "model/list/done":
                let models = (params["models"] as? [String]) ?? []
                return [.modelListResult(models: models)]
            case "error":
                return [.error(params: params)]
            case "account/rateLimits/updated":
                return [.rateLimitsUpdated(params: params)]
            default:
                return []
            }

        #if os(macOS)
        case let .exit(code, _):
            return [.exited(code: code)]
        #endif

        case .response, .stderr, .raw:
            return []
        }
    }

    // MARK: - RuntimeEvent Conversion (Deprecated — use CodexRuntimeAdapter)

    @available(*, deprecated, message: "Use CodexRuntimeAdapter().adapt() instead.")
    public func runtimeEvent(
        from event: CodexAppServerEvent,
        runtime: RuntimeIdentifier,
        sessionID: String? = nil,
        runID: String? = nil
    ) -> RuntimeEvent? {
        switch event {
        case let .serverRequest(id, method, params):
            if let approval = CodexApprovalRequest(requestID: id, method: method, params: params) {
                let commandStr: String?
                if let cmd = approval.command {
                    commandStr = "\(cmd)"
                } else {
                    commandStr = nil
                }
                return RuntimeEvent(
                    sessionID: sessionID, runID: runID, runtime: runtime,
                    type: .approvalRequested,
                    payload: .approvalRequested(
                        requestID: approval.requestID,
                        tool: approval.method,
                        command: commandStr,
                        riskLevel: nil
                    )
                )
            }
            return nil

        case let .notification(method, params):
            guard let params else { return nil }

            // File change detection
            if let fileChange = CodexFileChangeUpdated(method: method, params: params) {
                return RuntimeEvent(
                    sessionID: sessionID, runID: runID, runtime: runtime,
                    type: .fileChangeDetected,
                    payload: .fileChange(
                        path: fileChange.path ?? fileChange.itemID ?? "unknown",
                        changeKind: fileChange.changeKind ?? "changed"
                    )
                )
            }

            // Diff update
            if let diff = CodexTurnDiffUpdated(method: method, params: params) {
                return RuntimeEvent(
                    sessionID: sessionID, runID: runID, runtime: runtime,
                    type: .diffUpdated,
                    payload: .diffUpdated(files: diff.changedFiles)
                )
            }

            switch method {
            case "thread/started":
                let threadID = params["id"] as? String
                    ?? params["thread_id"] as? String
                    ?? (params["thread"] as? [String: Any])?["id"] as? String
                return RuntimeEvent(
                    sessionID: threadID ?? sessionID, runID: runID, runtime: runtime,
                    type: .sessionStarted,
                    payload: .sessionStarted(sessionID: threadID ?? "", cwd: params["cwd"] as? String)
                )

            case "turn/started":
                let turnID = params["turn_id"] as? String
                    ?? params["id"] as? String
                    ?? (params["turn"] as? [String: Any])?["id"] as? String
                let input = params["input"] as? String
                return RuntimeEvent(
                    sessionID: sessionID, runID: runID, runtime: runtime,
                    type: .turnStarted,
                    payload: .turnStarted(turnID: turnID, input: input)
                )

            case "item/agentMessage/delta":
                let text = params["delta"] as? String ?? ""
                return RuntimeEvent(
                    sessionID: sessionID, runID: runID, runtime: runtime,
                    type: .assistantDelta,
                    payload: .assistantDelta(text: text)
                )

            case "turn/completed":
                let turnID = params["turn_id"] as? String
                    ?? params["id"] as? String
                    ?? (params["turn"] as? [String: Any])?["id"] as? String
                return RuntimeEvent(
                    sessionID: sessionID, runID: runID, runtime: runtime,
                    type: .turnCompleted,
                    payload: .turnCompleted(turnID: turnID)
                )

            case "error":
                let message = (params["error"] as? [String: Any])?["message"] as? String
                    ?? params["error"] as? String
                    ?? "Unknown error"
                let code = (params["error"] as? [String: Any])?["code"] as? String
                return RuntimeEvent(
                    sessionID: sessionID, runID: runID, runtime: runtime,
                    type: .error,
                    payload: .error(message: message, code: code)
                )

            case "turn/error":
                let message = params["error"] as? String ?? "Turn failed"
                let turnID = params["turn_id"] as? String
                return RuntimeEvent(
                    sessionID: sessionID, runID: runID, runtime: runtime,
                    type: .turnError,
                    payload: .turnError(turnID: turnID, message: message)
                )

            case "thread/settings/updated":
                return RuntimeEvent(
                    sessionID: sessionID, runID: runID, runtime: runtime,
                    type: .settingsUpdated,
                    payload: .settingsUpdated(
                        model: params["model"] as? String,
                        effort: params["effort"] as? String
                    )
                )

            default:
                // Preserve unknown notifications as generic events
                // so they survive the round-trip without data loss.
                let stringParams = params.compactMapValues { $0 as? String }
                return RuntimeEvent(
                    sessionID: sessionID, runID: runID, runtime: runtime,
                    type: .settingsUpdated, // closest neutral type
                    payload: .generic(method: method, params: stringParams)
                )
            }

        #if os(macOS)
        case let .exit(code, _):
            return RuntimeEvent(
                sessionID: sessionID, runID: runID, runtime: runtime,
                type: .exited,
                payload: .exited(code: code)
            )
        #endif

        case .response, .stderr, .raw:
            return nil
        }
    }
}
