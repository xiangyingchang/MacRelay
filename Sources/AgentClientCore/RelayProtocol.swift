import Foundation

public enum RelayProtocolVersion {
    public static let current = 1
}

public struct RelayEnvelope<Payload: Codable>: Codable {
    public var id: String
    public var type: String
    public var version: Int
    public var seq: UInt64?
    public var correlationID: String?
    public var timestamp: Date
    public var payload: Payload

    public init(
        id: String = UUID().uuidString,
        type: String,
        version: Int = 1,
        seq: UInt64? = nil,
        correlationID: String? = nil,
        timestamp: Date = Date(),
        payload: Payload
    ) {
        self.id = id
        self.type = type
        self.version = version
        self.seq = seq
        self.correlationID = correlationID
        self.timestamp = timestamp
        self.payload = payload
    }
}

public enum RelayCommandType: String, Codable, CaseIterable {
    case pairClaim = "pairing.claim"
    case sessionList = "session.list"
    case sessionStart = "session.start"
    case sessionStop = "session.stop"
    case turnStart = "session.turn.start"
    case settingsUpdate = "session.settings.update"
    case approvalResolve = "approval.resolve"
    case projectBrowse = "project.browse"
    case diffList = "diff.list"
    case diffGet = "diff.get"
    case fileApprove = "file.approve"
    case fileStage = "file.stage"
    case fileDiscardSessionChanges = "file.discardSessionChanges"
    case fileDiscardAllChanges = "file.discardAllChanges"
    case snapshotGet = "snapshot.get"
    case replayFrom = "replay.from"
    case heartbeatPing = "heartbeat.ping"
}

public enum RelayEventType: String, Codable, CaseIterable {
    case connectionReady = "connection.ready"
    case heartbeat = "connection.heartbeat"
    case snapshot = "session.snapshot"
    case sessionStarted = "session.started"
    case sessionStatusChanged = "session.status.changed"
    case sessionSettingsUpdated = "session.settings.updated"
    case turnStarted = "turn.started"
    case turnDelta = "turn.delta"
    case turnCompleted = "turn.completed"
    case diffUpdated = "diff.updated"
    case fileChangeUpdated = "fileChange.updated"
    case approvalRequested = "approval.requested"
    case approvalResolved = "approval.resolved"
    case error = "error"
}

public struct ConnectionSnapshotPayload: Codable {
    public var deviceID: String?
    public var macName: String?
    public var isPaired: Bool
    public var isOnline: Bool
    public var lastSeenSeq: UInt64?

    public init(
        deviceID: String? = nil,
        macName: String? = nil,
        isPaired: Bool,
        isOnline: Bool,
        lastSeenSeq: UInt64? = nil
    ) {
        self.deviceID = deviceID
        self.macName = macName
        self.isPaired = isPaired
        self.isOnline = isOnline
        self.lastSeenSeq = lastSeenSeq
    }
}

public struct RelaySnapshotPayload: Codable {
    public var activeSessionID: String?
    public var session: RelaySessionSnapshotPayload?
    public var connection: ConnectionSnapshotPayload
    public var pendingApprovals: [RelayApprovalPayload]
    public var lastEventSeq: UInt64

    public init(
        activeSessionID: String?,
        session: RelaySessionSnapshotPayload?,
        connection: ConnectionSnapshotPayload,
        pendingApprovals: [RelayApprovalPayload],
        lastEventSeq: UInt64
    ) {
        self.activeSessionID = activeSessionID
        self.session = session
        self.connection = connection
        self.pendingApprovals = pendingApprovals
        self.lastEventSeq = lastEventSeq
    }
}

public struct RelaySessionSnapshotPayload: Codable {
    public var threadID: String?
    public var cwd: String?
    public var status: String
    public var model: String?
    public var effort: String?
    public var assistantText: String
    public var userMessage: String?
    public var turns: [RelayTurnSnapshotPayload]
    public var availableModels: [String]?
    public var changedFiles: [String]
    public var rateLimitPlanType: String?
    public var errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case threadID
        case cwd
        case status
        case model
        case effort
        case assistantText
        case userMessage
        case turns
        case availableModels
        case changedFiles
        case rateLimitPlanType
        case errorMessage
    }

    public init(
        threadID: String?,
        cwd: String?,
        status: String,
        model: String?,
        effort: String?,
        assistantText: String,
        userMessage: String? = nil,
        turns: [RelayTurnSnapshotPayload] = [],
        availableModels: [String]? = nil,
        changedFiles: [String],
        rateLimitPlanType: String? = nil,
        errorMessage: String? = nil
    ) {
        self.threadID = threadID
        self.cwd = cwd
        self.status = status
        self.model = model
        self.effort = effort
        self.assistantText = assistantText
        self.userMessage = userMessage
        self.turns = turns
        self.availableModels = availableModels
        self.changedFiles = changedFiles
        self.rateLimitPlanType = rateLimitPlanType
        self.errorMessage = errorMessage
    }

    public init(snapshot: SessionSnapshot) {
        self.threadID = snapshot.threadID
        self.cwd = snapshot.cwd
        self.status = snapshot.status.rawValue
        self.model = snapshot.settings?.model
        self.effort = snapshot.settings?.effort
        self.assistantText = snapshot.activeTurn?.assistantText ?? ""
        self.userMessage = snapshot.activeTurn?.userMessage
        var turns = snapshot.completedTurns.map(RelayTurnSnapshotPayload.init)
        if let active = snapshot.activeTurn, turns.last?.id != active.id || turns.last?.isCompleted != active.isCompleted {
            turns.append(RelayTurnSnapshotPayload(turn: active))
        }
        self.turns = turns
        self.availableModels = snapshot.availableModels
        self.changedFiles = snapshot.turnDiff?.changedFiles ?? snapshot.fileChanges.values.compactMap(\.path)
        self.rateLimitPlanType = snapshot.rateLimit?.planType
        self.errorMessage = snapshot.lastError?.message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.threadID = try container.decodeIfPresent(String.self, forKey: .threadID)
        self.cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        self.status = try container.decode(String.self, forKey: .status)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.effort = try container.decodeIfPresent(String.self, forKey: .effort)
        self.assistantText = try container.decode(String.self, forKey: .assistantText)
        self.userMessage = try container.decodeIfPresent(String.self, forKey: .userMessage)
        self.turns = try container.decodeIfPresent([RelayTurnSnapshotPayload].self, forKey: .turns) ?? []
        self.availableModels = try container.decodeIfPresent([String].self, forKey: .availableModels)
        self.changedFiles = try container.decode([String].self, forKey: .changedFiles)
        self.rateLimitPlanType = try container.decodeIfPresent(String.self, forKey: .rateLimitPlanType)
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

public struct RelayTurnSnapshotPayload: Codable, Equatable {
    public var id: String?
    public var userMessage: String?
    public var assistantText: String
    public var isCompleted: Bool

    public init(
        id: String?,
        userMessage: String?,
        assistantText: String,
        isCompleted: Bool
    ) {
        self.id = id
        self.userMessage = userMessage
        self.assistantText = assistantText
        self.isCompleted = isCompleted
    }

    public init(turn: TurnSnapshot) {
        self.id = turn.id
        self.userMessage = turn.userMessage
        self.assistantText = turn.assistantText
        self.isCompleted = turn.isCompleted
    }
}

public struct RelayApprovalPayload: Codable {
    public var requestID: Int
    public var method: String
    public var reason: String?
    public var command: String?
    public var isPending: Bool

    public init(approval: ApprovalSnapshot) {
        self.requestID = approval.requestID
        self.method = approval.method
        self.reason = approval.reason
        self.command = approval.command
        self.isPending = approval.isPending
    }
}

public struct RelayReplayRequestPayload: Codable {
    public var afterSeq: UInt64
    public var maxEvents: Int?

    public init(afterSeq: UInt64, maxEvents: Int? = nil) {
        self.afterSeq = afterSeq
        self.maxEvents = maxEvents
    }
}

public struct RelaySnapshotGetCommandPayload: Codable, Equatable {
    public var sessionID: String?
    public var includeHistory: Bool

    public init(sessionID: String? = nil, includeHistory: Bool = false) {
        self.sessionID = sessionID
        self.includeHistory = includeHistory
    }
}

public struct RelaySessionStartCommandPayload: Codable, Equatable {
    public var cwd: String
    public var model: String?
    public var effort: String?
    public var planMode: Bool
    public var permissionMode: String
    public var approvalPolicy: String?
    public var sandboxMode: String?
    public var initialPrompt: String?

    public init(
        cwd: String,
        model: String? = nil,
        effort: String? = nil,
        planMode: Bool,
        permissionMode: String,
        approvalPolicy: String? = nil,
        sandboxMode: String? = nil,
        initialPrompt: String? = nil
    ) {
        self.cwd = cwd
        self.model = model
        self.effort = effort
        self.planMode = planMode
        self.permissionMode = permissionMode
        self.approvalPolicy = approvalPolicy
        self.sandboxMode = sandboxMode
        self.initialPrompt = initialPrompt
    }
}

public struct RelayTurnStartCommandPayload: Codable, Equatable {
    public var sessionID: String
    public var input: String
    public var model: String?
    public var effort: String?
    public var planMode: Bool?
    public var permissionMode: String?

    public init(
        sessionID: String,
        input: String,
        model: String? = nil,
        effort: String? = nil,
        planMode: Bool? = nil,
        permissionMode: String? = nil
    ) {
        self.sessionID = sessionID
        self.input = input
        self.model = model
        self.effort = effort
        self.planMode = planMode
        self.permissionMode = permissionMode
    }
}

public struct RelaySessionStopCommandPayload: Codable, Equatable {
    public var sessionID: String
    public var reason: String?

    public init(sessionID: String, reason: String? = nil) {
        self.sessionID = sessionID
        self.reason = reason
    }
}

public struct RelaySettingsUpdateCommandPayload: Codable, Equatable {
    public var sessionID: String
    public var model: String?
    public var effort: String?
    public var planMode: Bool?
    public var permissionMode: String?
    public var approvalPolicy: String?
    public var sandboxMode: String?

    public init(
        sessionID: String,
        model: String? = nil,
        effort: String? = nil,
        planMode: Bool? = nil,
        permissionMode: String? = nil,
        approvalPolicy: String? = nil,
        sandboxMode: String? = nil
    ) {
        self.sessionID = sessionID
        self.model = model
        self.effort = effort
        self.planMode = planMode
        self.permissionMode = permissionMode
        self.approvalPolicy = approvalPolicy
        self.sandboxMode = sandboxMode
    }
}

public struct RelayApprovalResolveCommandPayload: Codable, Equatable {
    public var sessionID: String
    public var requestID: Int
    public var decision: String

    public init(sessionID: String, requestID: Int, decision: String) {
        self.sessionID = sessionID
        self.requestID = requestID
        self.decision = decision
    }
}

public struct RelayDiffGetCommandPayload: Codable, Equatable {
    public var sessionID: String
    public var path: String

    public init(sessionID: String, path: String) {
        self.sessionID = sessionID
        self.path = path
    }
}

public struct RelayProjectBrowseCommandPayload: Codable, Equatable {
    public var path: String
    public var includeHidden: Bool

    public init(path: String, includeHidden: Bool = false) {
        self.path = path
        self.includeHidden = includeHidden
    }
}

public struct RelayFileCommandPayload: Codable, Equatable {
    public var sessionID: String
    public var path: String
    public var requireBiometricConfirmation: Bool

    public init(
        sessionID: String,
        path: String,
        requireBiometricConfirmation: Bool = false
    ) {
        self.sessionID = sessionID
        self.path = path
        self.requireBiometricConfirmation = requireBiometricConfirmation
    }
}

public struct RelayEventRecord<Payload: Codable>: Codable {
    public var seq: UInt64
    public var envelope: RelayEnvelope<Payload>

    public init(seq: UInt64, envelope: RelayEnvelope<Payload>) {
        self.seq = seq
        self.envelope = envelope
    }
}

public final class RelaySequence {
    private var nextSeq: UInt64

    public init(startingAt nextSeq: UInt64 = 1) {
        self.nextSeq = nextSeq
    }

    public func assign<Payload>(_ envelope: RelayEnvelope<Payload>) -> RelayEnvelope<Payload> {
        var copy = envelope
        copy.seq = nextSeq
        nextSeq += 1
        return copy
    }
}
