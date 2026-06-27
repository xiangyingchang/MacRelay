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

@MainActor
final class FakeRuntimeBridge: MacRelayRuntimeBridge {
    struct DraftCall: Equatable {
        let cwd: String
        let text: String
        let model: String?
        let effort: String?
        let threadSandbox: String
        let turnSandbox: String
        let approvalPolicy: String
    }

    struct SettingsCall: Equatable {
        let model: String?
        let effort: String?
        let approvalPolicy: String?
        let sandboxPolicy: String?
    }

    struct ApprovalCall: Equatable {
        let requestID: Int
        let decision: String
    }

    var draftCalls: [DraftCall] = []
    var settingsCalls: [SettingsCall] = []
    var approvalCalls: [ApprovalCall] = []

    func enqueueDraft(
        cwd: String,
        text: String,
        model: String?,
        effort: String?,
        threadSandbox: String,
        turnSandbox: String,
        approvalPolicy: String
    ) throws {
        draftCalls.append(DraftCall(
            cwd: cwd,
            text: text,
            model: model,
            effort: effort,
            threadSandbox: threadSandbox,
            turnSandbox: turnSandbox,
            approvalPolicy: approvalPolicy
        ))
    }

    func updateSettings(model: String?, effort: String?, approvalPolicy: String?, sandboxPolicy: String?) throws -> Int {
        settingsCalls.append(SettingsCall(
            model: model,
            effort: effort,
            approvalPolicy: approvalPolicy,
            sandboxPolicy: sandboxPolicy
        ))
        return settingsCalls.count
    }

    func resolveApproval(requestID: Int, decision: String) throws {
        approvalCalls.append(ApprovalCall(requestID: requestID, decision: decision))
    }
}

@MainActor
func runRelayRuntimeCommandDispatcherProbe() throws {
        let runtime = FakeRuntimeBridge()
        let dispatcher = MacRelayRuntimeCommandDispatcher(runtime: runtime, defaultCWD: { FileManager.default.currentDirectoryPath })
        let encoder = JSONEncoder()

        let turnPayload = RelayTurnStartCommandPayload(
            sessionID: "thread-1",
            input: "hello from relay",
            model: "gpt-5.4-mini",
            effort: "low",
            planMode: false,
            permissionMode: "Read Only"
        )
        let turnResult = try dispatcher.dispatch(commandType: .turnStart, payloadData: encoder.encode(turnPayload))
        try expect(turnResult == .dispatched("session.turn.start"), "turn dispatch result mismatch")
        try expect(runtime.draftCalls.count == 1, "turn should enqueue one draft")
        try expect(runtime.draftCalls[0].cwd == FileManager.default.currentDirectoryPath, "turn cwd mismatch")
        try expect(runtime.draftCalls[0].text == "hello from relay", "turn input mismatch")
        try expect(runtime.draftCalls[0].threadSandbox == "read-only", "thread sandbox mismatch")
        try expect(runtime.draftCalls[0].turnSandbox == "readOnly", "turn sandbox mismatch")
        try expect(runtime.draftCalls[0].approvalPolicy == "on-request", "approval policy mismatch")

        let settingsPayload = RelaySettingsUpdateCommandPayload(
            sessionID: "thread-1",
            model: "gpt-5.5",
            effort: "high",
            planMode: nil,
            permissionMode: "Full Access"
        )
        let settingsResult = try dispatcher.dispatch(commandType: .settingsUpdate, payloadData: encoder.encode(settingsPayload))
        try expect(settingsResult == .dispatched("session.settings.update"), "settings dispatch result mismatch")
        try expect(runtime.settingsCalls.count == 1, "settings should call updateSettings")
        try expect(runtime.settingsCalls[0].model == "gpt-5.5", "settings model mismatch")
        try expect(runtime.settingsCalls[0].effort == "high", "settings effort mismatch")
        try expect(runtime.settingsCalls[0].approvalPolicy == "never", "settings approval mismatch")
        try expect(runtime.settingsCalls[0].sandboxPolicy == "dangerFullAccess", "settings sandbox mismatch")

        let approvalPayload = RelayApprovalResolveCommandPayload(sessionID: "thread-1", requestID: 0, decision: "accept")
        let approvalResult = try dispatcher.dispatch(commandType: .approvalResolve, payloadData: encoder.encode(approvalPayload))
        try expect(approvalResult == .dispatched("approval.resolve"), "approval dispatch result mismatch")
        try expect(runtime.approvalCalls == [FakeRuntimeBridge.ApprovalCall(requestID: 0, decision: "accept")], "approval call mismatch")

    print("RelayRuntimeCommandDispatcherProbe passed draftCalls=\(runtime.draftCalls.count) settingsCalls=\(runtime.settingsCalls.count) approvalCalls=\(runtime.approvalCalls.count)")
}

try MainActor.assumeIsolated {
    try runRelayRuntimeCommandDispatcherProbe()
}
