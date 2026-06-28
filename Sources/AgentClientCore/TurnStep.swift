import Foundation

// MARK: - Agent Step Tracking

public enum TurnStepKind: String, Codable, CaseIterable {
    case initialize
    case modelList
    case threadStart
    case turnStart
    case thinking
    case toolCall
    case fileChange
    case approval
    case turnCompleted
    case error
    case stderr
    case assistantResponse

    public var displayTitle: String {
        switch self {
        case .initialize: return "Initialize Runtime"
        case .modelList: return "Fetch Models"
        case .threadStart: return "Create Session"
        case .turnStart: return "Start Turn"
        case .thinking: return "Thinking"
        case .toolCall: return "Tool Call"
        case .fileChange: return "File Change"
        case .approval: return "Approval"
        case .turnCompleted: return "Completed"
        case .error: return "Error"
        case .stderr: return "Process Output"
        case .assistantResponse: return "Generating Response"
        }
    }

    public var icon: String {
        switch self {
        case .initialize: return "bolt.fill"
        case .modelList: return "list.bullet"
        case .threadStart: return "plus.circle"
        case .turnStart: return "play.fill"
        case .thinking: return "brain"
        case .toolCall: return "wrench.fill"
        case .fileChange: return "doc.badge.plus"
        case .approval: return "hand.raised.fill"
        case .turnCompleted: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .stderr: return "terminal"
        case .assistantResponse: return "ellipsis.bubble"
        }
    }
}

public enum StepStatus: String, Codable {
    case pending
    case active
    case completed
    case failed
}

public struct TurnStep: Identifiable, Codable, Sendable {
    public let id: UUID
    public let kind: TurnStepKind
    public let title: String
    public let detail: String?
    public let icon: String
    public let timestamp: Date
    public var status: StepStatus

    public init(kind: TurnStepKind, detail: String? = nil, status: StepStatus = .completed) {
        self.id = UUID()
        self.kind = kind
        self.title = kind.displayTitle
        self.detail = detail
        self.icon = kind.icon
        self.timestamp = Date()
        self.status = status
    }
}
