import AgentClientCore
import Foundation

enum ProbeError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw ProbeError.failed(message)
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
encoder.dateEncodingStrategy = .iso8601

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

func roundTrip<Payload: Codable>(
    _ type: RelayCommandType,
    payload: Payload
) throws -> RelayEnvelope<Payload> {
    let envelope = RelayEnvelope(type: type.rawValue, payload: payload)
    let data = try encoder.encode(envelope)
    let decoded = try decoder.decode(RelayEnvelope<Payload>.self, from: data)
    try expect(decoded.type == type.rawValue, "type mismatch for \(type.rawValue)")
    try expect(decoded.version == 1, "version mismatch for \(type.rawValue)")
    return decoded
}

let sessionID = "mock-thread"
let fixtureCommands: [(RelayCommandType, Any)] = [
    (.sessionStart, RelaySessionStartCommandPayload(
        cwd: "/Users/example/project",
        model: "gpt-5.5",
        effort: "high",
        planMode: true,
        permissionMode: "Full Access",
        approvalPolicy: "never",
        sandboxMode: "danger-full-access",
        initialPrompt: "Fix failing tests"
    )),
    (.turnStart, RelayTurnStartCommandPayload(
        sessionID: sessionID,
        input: "Continue from the latest failure",
        model: "gpt-5.5",
        effort: "medium",
        planMode: false,
        permissionMode: "Default"
    )),
    (.sessionStop, RelaySessionStopCommandPayload(
        sessionID: sessionID,
        reason: "user_requested"
    )),
    (.settingsUpdate, RelaySettingsUpdateCommandPayload(
        sessionID: sessionID,
        model: "gpt-5.4-mini",
        effort: "low",
        planMode: true,
        permissionMode: "Read Only",
        approvalPolicy: "on-request",
        sandboxMode: "workspace-write"
    )),
    (.approvalResolve, RelayApprovalResolveCommandPayload(
        sessionID: sessionID,
        requestID: 0,
        decision: "accept"
    )),
    (.diffGet, RelayDiffGetCommandPayload(
        sessionID: sessionID,
        path: "Sources/App.swift"
    )),
    (.projectBrowse, RelayProjectBrowseCommandPayload(
        path: "/Users/example",
        includeHidden: false
    )),
    (.fileApprove, RelayFileCommandPayload(
        sessionID: sessionID,
        path: "Sources/App.swift"
    )),
    (.fileStage, RelayFileCommandPayload(
        sessionID: sessionID,
        path: "Sources/App.swift"
    )),
    (.fileDiscardSessionChanges, RelayFileCommandPayload(
        sessionID: sessionID,
        path: "Sources/App.swift"
    )),
    (.fileDiscardAllChanges, RelayFileCommandPayload(
        sessionID: sessionID,
        path: "Sources/App.swift",
        requireBiometricConfirmation: true
    )),
    (.replayFrom, RelayReplayRequestPayload(
        afterSeq: 42,
        maxEvents: 100
    )),
    (.snapshotGet, RelaySnapshotGetCommandPayload(
        sessionID: sessionID,
        includeHistory: false
    ))
]

var encodedTypes: [String] = []

for (type, erasedPayload) in fixtureCommands {
    switch erasedPayload {
    case let payload as RelaySessionStartCommandPayload:
        _ = try roundTrip(type, payload: payload)
    case let payload as RelayTurnStartCommandPayload:
        _ = try roundTrip(type, payload: payload)
    case let payload as RelaySessionStopCommandPayload:
        _ = try roundTrip(type, payload: payload)
    case let payload as RelaySettingsUpdateCommandPayload:
        _ = try roundTrip(type, payload: payload)
    case let payload as RelayApprovalResolveCommandPayload:
        _ = try roundTrip(type, payload: payload)
    case let payload as RelayDiffGetCommandPayload:
        _ = try roundTrip(type, payload: payload)
    case let payload as RelayProjectBrowseCommandPayload:
        _ = try roundTrip(type, payload: payload)
    case let payload as RelayFileCommandPayload:
        _ = try roundTrip(type, payload: payload)
    case let payload as RelayReplayRequestPayload:
        _ = try roundTrip(type, payload: payload)
    case let payload as RelaySnapshotGetCommandPayload:
        _ = try roundTrip(type, payload: payload)
    default:
        throw ProbeError.failed("unhandled payload for \(type.rawValue)")
    }
    encodedTypes.append(type.rawValue)
}

let required: Set<RelayCommandType> = [
    .sessionStart,
    .turnStart,
    .sessionStop,
    .settingsUpdate,
    .approvalResolve,
    .diffGet,
    .projectBrowse,
    .fileApprove,
    .fileStage,
    .fileDiscardSessionChanges,
    .fileDiscardAllChanges,
    .replayFrom,
    .snapshotGet
]

let covered = Set(encodedTypes.compactMap(RelayCommandType.init(rawValue:)))
try expect(required.isSubset(of: covered), "missing required command fixture")

print("RelayCommandFixtureProbe passed: \(encodedTypes.joined(separator: ", "))")
