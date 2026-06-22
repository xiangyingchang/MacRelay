import Foundation

public enum MobileClientState: String, Equatable, CaseIterable {
    case unpaired
    case pairing
    case paired
    case connecting
    case connected
    case reconnecting
    case authFailed
    case offline
}

public struct MobileStateTransition: Equatable {
    public let from: MobileClientState
    public let to: MobileClientState
    public let timestamp: Date

    public init(from: MobileClientState, to: MobileClientState, timestamp: Date = Date()) {
        self.from = from
        self.to = to
        self.timestamp = timestamp
    }
}

public final class MobileConnectionStateMachine {
    public private(set) var state: MobileClientState = .unpaired
    public private(set) var history: [MobileStateTransition] = []
    public private(set) var backoffAttempt: Int = 0
    public var onTransition: ((MobileStateTransition) -> Void)?

    public init() {}

    private let maxBackoffSeconds: TimeInterval = 60
    private let baseBackoffSeconds: TimeInterval = 1

    private static let allowedTransitions: [MobileClientState: Set<MobileClientState>] = [
        .unpaired:    [.pairing],
        .pairing:     [.paired, .unpaired],
        .paired:      [.connecting],
        .connecting:  [.connected, .authFailed, .offline],
        .connected:   [.reconnecting, .offline],
        .reconnecting:[.connected, .authFailed, .offline],
        .authFailed:  [.unpaired],
        .offline:     [.connecting, .reconnecting, .unpaired],
    ]

    @discardableResult
    public func transition(to next: MobileClientState) -> MobileStateTransition? {
        guard let allowed = Self.allowedTransitions[state], allowed.contains(next) else {
            return nil
        }

        let transition = MobileStateTransition(from: state, to: next)
        state = next
        history.append(transition)

        switch next {
        case .reconnecting:
            backoffAttempt += 1
        case .connected:
            backoffAttempt = 0
        default:
            break
        }

        onTransition?(transition)
        return transition
    }

    public var nextBackoff: TimeInterval {
        let raw = baseBackoffSeconds * pow(2.0, Double(backoffAttempt - 1))
        return min(raw, maxBackoffSeconds)
    }

    public func attemptPairing() -> Bool { transition(to: .pairing) != nil }
    public func pairSuccess() -> Bool { transition(to: .paired) != nil }
    public func pairFailed() -> Bool { transition(to: .unpaired) != nil }
    public func startConnect() -> Bool { transition(to: .connecting) != nil }
    public func connected() -> Bool { transition(to: .connected) != nil }
    public func authRejected() -> Bool { transition(to: .authFailed) != nil }
    public func networkLost() -> Bool { transition(to: .offline) != nil }
    public func startReconnect() -> Bool { transition(to: .reconnecting) != nil }
    public func credentialExpired() { _ = transition(to: .authFailed) }
}
