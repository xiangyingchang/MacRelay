import Foundation

public struct StoredRelayEvent: Codable {
    public var seq: UInt64
    public var envelopeID: String
    public var type: String
    public var version: Int
    public var timestamp: Date
    public var payloadData: Data

    public init<Payload: Codable>(envelope: RelayEnvelope<Payload>) throws {
        guard let seq = envelope.seq else {
            throw EventStoreError.missingSequence
        }
        self.seq = seq
        self.envelopeID = envelope.id
        self.type = envelope.type
        self.version = envelope.version
        self.timestamp = envelope.timestamp
        self.payloadData = try JSONEncoder().encode(envelope.payload)
    }

    public func decodePayload<Payload: Codable>(_ type: Payload.Type) throws -> Payload {
        try JSONDecoder().decode(Payload.self, from: payloadData)
    }

    /// Human-readable summary derived from the event payload, suitable for display.
    public var summary: String {
        guard let dict = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return type
        }
        switch type {
        case "notification":
            let method = dict["method"] as? String ?? ""
            switch method {
            case "turn/started":
                return "Turn started"
            case "turn/completed":
                return "Turn completed"
            case "thread/started":
                return "Thread started"
            case "thread/statusChanged":
                return "Status: \(dict["status"] as? String ?? "-")"
            case "assistant/delta", "item/agentMessage/delta":
                let delta = dict["delta"] as? String ?? ""
                return delta.isEmpty ? "assistant delta" : String(delta.prefix(60))
            case "settings/updated", "settingsUpdated":
                return "Settings updated"
            case "error":
                return "Error: \(dict["message"] as? String ?? "-")"
            case "rateLimits/updated":
                return "Rate limits updated"
            default:
                return method.replacingOccurrences(of: "/", with: " ")
            }
        case "request":
            let method = dict["method"] as? String ?? ""
            if let params = dict["params"] as? [String: Any] {
                if method == "command/execution/requestApproval" {
                    return "Approval: \(params["message"] as? String ?? "request")"
                }
                if method == "file/change/requestApproval" {
                    return "File change: \(params["path"] as? String ?? "-")"
                }
            }
            return "request: \(method.replacingOccurrences(of: "/", with: " "))"
        case "response":
            return "Response"
        default:
            return type
        }
    }
}

public enum EventReplayResult {
    case events([StoredRelayEvent])
    case needsFullSnapshot(reason: String)
}

public final class EventStore {
    public let capacity: Int
    private var events: [StoredRelayEvent] = []

    public init(capacity: Int) {
        precondition(capacity > 0, "EventStore capacity must be positive")
        self.capacity = capacity
    }

    public var oldestSeq: UInt64? {
        events.first?.seq
    }

    public var newestSeq: UInt64? {
        events.last?.seq
    }

    public var count: Int {
        events.count
    }

    public func append(_ event: StoredRelayEvent) {
        if let newestSeq, event.seq <= newestSeq {
            return
        }

        events.append(event)
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    public func replay(afterSeq: UInt64, maxEvents: Int? = nil) -> EventReplayResult {
        guard let oldestSeq, let newestSeq else {
            return .events([])
        }

        if afterSeq > newestSeq {
            return .needsFullSnapshot(reason: "afterSeq is newer than newest cached event")
        }

        if afterSeq != 0 && afterSeq < oldestSeq {
            return .needsFullSnapshot(reason: "afterSeq is older than oldest cached event")
        }

        let replayEvents = events.filter { $0.seq > afterSeq }
        if let maxEvents {
            return .events(Array(replayEvents.prefix(maxEvents)))
        }
        return .events(replayEvents)
    }
}

public enum EventStoreError: Error {
    case missingSequence
}
