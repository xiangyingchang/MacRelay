import Foundation

/// Adapts Codex CLI JSON-RPC events (CodexAppServerEvent) into the unified
/// RuntimeEvent protocol. This is the boundary between the Codex-specific
/// transport layer and the runtime-agnostic Agent Harness core.
///
/// After this adapter, no downstream component (Reducer, Trace, Timeline)
/// needs to know about Codex JSON-RPC internals.
public struct CodexRuntimeAdapter {
    public init() {}

    /// Convert a CodexAppServerEvent into zero or more RuntimeEvents.
    ///
    /// Most events produce exactly one RuntimeEvent.
    /// Responses and stderr produce none (they are transport-level, not domain events).
    public func adapt(
        _ event: CodexAppServerEvent,
        sessionID: String? = nil,
        runID: String? = nil
    ) -> [RuntimeEvent] {
        switch event {
        case let .serverRequest(id, method, params):
            return adaptServerRequest(id: id, method: method, params: params,
                                      sessionID: sessionID, runID: runID)

        case let .notification(method, params):
            guard let params else { return [] }
            return adaptNotification(method: method, params: params,
                                     sessionID: sessionID, runID: runID)

        #if os(macOS)
        case let .exit(code, _):
            return [RuntimeEvent(
                sessionID: sessionID, runID: runID, runtime: .codex,
                type: .exited,
                payload: .exited(code: code)
            )]
        #endif

        case .response, .stderr, .raw:
            return [] // Transport-level, not domain events
        }
    }

    // MARK: - Server Requests (Approvals)

    private func adaptServerRequest(
        id: Int, method: String, params: [String: Any]?,
        sessionID: String?, runID: String?
    ) -> [RuntimeEvent] {
        guard let approval = CodexApprovalRequest(requestID: id, method: method, params: params) else {
            return []
        }
        let commandStr: String?
        if let cmd = approval.command {
            commandStr = "\(cmd)"
        } else {
            commandStr = nil
        }
        return [RuntimeEvent(
            sessionID: sessionID, runID: runID, runtime: .codex,
            type: .approvalRequested,
            payload: .approvalRequested(
                requestID: approval.requestID,
                tool: approval.method,
                command: commandStr,
                riskLevel: nil
            )
        )]
    }

    // MARK: - Notifications

    private func adaptNotification(
        method: String, params: [String: Any],
        sessionID: String?, runID: String?
    ) -> [RuntimeEvent] {
        // Check structured event types first
        if let fileChange = CodexFileChangeUpdated(method: method, params: params) {
            return [RuntimeEvent(
                sessionID: sessionID, runID: runID, runtime: .codex,
                type: .fileChangeDetected,
                payload: .fileChange(
                    path: fileChange.path ?? fileChange.itemID ?? "unknown",
                    changeKind: fileChange.changeKind ?? "changed"
                )
            )]
        }

        if let diff = CodexTurnDiffUpdated(method: method, params: params) {
            return [RuntimeEvent(
                sessionID: sessionID, runID: runID, runtime: .codex,
                type: .diffUpdated,
                payload: .diffUpdated(files: diff.changedFiles)
            )]
        }

        // Map by method name
        switch method {
        case "thread/started":
            let threadID = params["id"] as? String
                ?? params["thread_id"] as? String
                ?? (params["thread"] as? [String: Any])?["id"] as? String
            return [RuntimeEvent(
                sessionID: threadID ?? sessionID, runID: runID, runtime: .codex,
                type: .sessionStarted,
                payload: .sessionStarted(sessionID: threadID ?? "", cwd: params["cwd"] as? String)
            )]

        case "turn/started":
            let turnID = params["turn_id"] as? String
                ?? params["id"] as? String
                ?? (params["turn"] as? [String: Any])?["id"] as? String
            let input = params["input"] as? String
            return [RuntimeEvent(
                sessionID: sessionID, runID: runID, runtime: .codex,
                type: .turnStarted,
                payload: .turnStarted(turnID: turnID, input: input)
            )]

        case "item/agentMessage/delta":
            let text = params["delta"] as? String ?? ""
            return [RuntimeEvent(
                sessionID: sessionID, runID: runID, runtime: .codex,
                type: .assistantDelta,
                payload: .assistantDelta(text: text)
            )]

        case "turn/completed":
            let turnID = params["turn_id"] as? String
                ?? params["id"] as? String
                ?? (params["turn"] as? [String: Any])?["id"] as? String
            return [RuntimeEvent(
                sessionID: sessionID, runID: runID, runtime: .codex,
                type: .turnCompleted,
                payload: .turnCompleted(turnID: turnID)
            )]

        case "turn/error":
            let message = params["error"] as? String ?? "Turn failed"
            let turnID = params["turn_id"] as? String
            return [RuntimeEvent(
                sessionID: sessionID, runID: runID, runtime: .codex,
                type: .turnError,
                payload: .turnError(turnID: turnID, message: message)
            )]

        case "error":
            let message = (params["error"] as? [String: Any])?["message"] as? String
                ?? params["error"] as? String
                ?? "Unknown error"
            let code = (params["error"] as? [String: Any])?["code"] as? String
            return [RuntimeEvent(
                sessionID: sessionID, runID: runID, runtime: .codex,
                type: .error,
                payload: .error(message: message, code: code)
            )]

        case "thread/settings/updated":
            return [RuntimeEvent(
                sessionID: sessionID, runID: runID, runtime: .codex,
                type: .settingsUpdated,
                payload: .settingsUpdated(
                    model: params["model"] as? String,
                    effort: params["effort"] as? String
                )
            )]

        default:
            // Unknown notifications are preserved as generic events
            // so they survive the round-trip without data loss.
            let stringParams = params.compactMapValues { $0 as? String }
            return [RuntimeEvent(
                sessionID: sessionID, runID: runID, runtime: .codex,
                type: .unknown,
                payload: .generic(method: method, params: stringParams)
            )]
        }
    }
}
