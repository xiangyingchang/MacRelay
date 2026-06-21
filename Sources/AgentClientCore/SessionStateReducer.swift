import Foundation

public struct SessionSnapshot {
    public var threadID: String?
    public var cwd: String?
    public var status: SessionStatus = .idle
    public var settings: SessionSettingsSnapshot?
    public var activeTurn: TurnSnapshot?
    public var pendingApprovals: [String: ApprovalSnapshot] = [:]
    public var fileChanges: [String: FileChangeSnapshot] = [:]
    public var turnDiff: CodexTurnDiffUpdated?
    public var lastError: SessionErrorSnapshot?
    public var rateLimit: RateLimitSnapshot?
    public var hasExited = false

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
    public var approvalPolicy: String?
    public var sandboxType: String?
    public var cwd: String?
}

public struct TurnSnapshot {
    public var id: String?
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
    case exited(code: Int32)
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
            state.activeTurn = TurnSnapshot(id: turn?["id"] as? String)
            state.status = .active

        case let .assistantDelta(delta):
            if state.activeTurn == nil {
                state.activeTurn = TurnSnapshot()
            }
            state.activeTurn?.assistantText += delta

        case .turnCompleted:
            state.activeTurn?.isCompleted = true
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

        case .exited:
            state.hasExited = true
            state.status = .exited
        }
    }

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
            case "error":
                return [.error(params: params)]
            case "account/rateLimits/updated":
                return [.rateLimitsUpdated(params: params)]
            default:
                return []
            }

        case let .exit(code, _):
            return [.exited(code: code)]

        case .response, .stderr, .raw:
            return []
        }
    }
}
