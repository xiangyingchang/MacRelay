import Foundation

/// Converts an ordered `RuntimeEvent` stream into a flat `[TimelineItem]`
/// suitable for rendering on any platform (iOS, macOS, Web).
///
/// The builder is **stateless** — call `build(from:)` with the full event
/// list each time.  This keeps the data layer pure and testable.
///
/// ## Design rules
/// - No SwiftUI, UIKit, or DOM types.
/// - Every output item is `Codable` so it round-trips through JSON
///   (relay, cache, snapshot).
/// - Deltas are accumulated into a single `assistantMessage` per turn.
///   When `turn.completed` arrives the buffered text is flushed.
///   If the stream ends without `turn.completed`, the caller decides
///   whether to flush (the builder does **not** invent a synthetic item).
public struct TimelineBuilder {
    public init() {}

    // MARK: - Public API

    /// Build timeline items from an ordered event stream.
    ///
    /// Events that don't map to a visible timeline cell are silently skipped
    /// (e.g. `settingsUpdated`, `diffUpdated`, `sessionStarted`).
    public func build(from events: [RuntimeEvent]) -> [TimelineItem] {
        var items: [TimelineItem] = []
        // Accumulator for streaming assistant text within a single turn.
        var pendingAssistantText = ""

        for event in events {
            let produced = process(event, pendingAssistantText: &pendingAssistantText)
            items.append(contentsOf: produced)
        }

        return items
    }

    // MARK: - Internal

    /// Process a single event, mutating the accumulator as needed.
    /// Returns 0..N timeline items.
    private func process(
        _ event: RuntimeEvent,
        pendingAssistantText: inout String
    ) -> [TimelineItem] {
        switch event.type {

        // ── User message ──────────────────────────────────────────────
        case .turnStarted:
            return handleTurnStarted(event)

        // ── Assistant streaming ────────────────────────────────────────
        case .assistantDelta:
            return handleAssistantDelta(event, pendingAssistantText: &pendingAssistantText)

        case .assistantMessageCompleted:
            return handleAssistantMessageCompleted(event, pendingAssistantText: &pendingAssistantText)

        // ── Turn lifecycle ─────────────────────────────────────────────
        case .turnCompleted:
            return handleTurnCompleted(event, pendingAssistantText: &pendingAssistantText)

        case .turnError:
            return handleTurnError(event, pendingAssistantText: &pendingAssistantText)

        // ── Tool calls ─────────────────────────────────────────────────
        case .toolCallRequested:
            return handleToolCallRequested(event)

        case .toolCallCompleted:
            return handleToolCallCompleted(event)

        case .toolCallFailed:
            return handleToolCallFailed(event)

        // ── Approval ───────────────────────────────────────────────────
        case .approvalRequested:
            return handleApprovalRequested(event)

        case .approvalResolved:
            return handleApprovalResolved(event)

        // ── File changes ───────────────────────────────────────────────
        case .fileChangeDetected:
            return handleFileChange(event)

        // ── Errors ─────────────────────────────────────────────────────
        case .error:
            return handleGlobalError(event)

        // ── Ignored events ─────────────────────────────────────────────
        case .sessionStarted, .sessionStopped, .sessionSelected,
             .diffUpdated, .exited, .settingsUpdated, .unknown:
            return []
        }
    }

    // MARK: - Handlers

    private func handleTurnStarted(_ event: RuntimeEvent) -> [TimelineItem] {
        guard case let .turnStarted(turnID, input) = event.payload,
              let input, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return [TimelineItem(
            id: "user-\(turnID ?? event.id)",
            type: .userMessage,
            timestamp: event.timestamp,
            data: .userMessage(text: input)
        )]
    }

    private func handleAssistantDelta(
        _ event: RuntimeEvent,
        pendingAssistantText: inout String
    ) -> [TimelineItem] {
        guard case let .assistantDelta(text) = event.payload else { return [] }
        pendingAssistantText += text
        return []
    }

    private func handleAssistantMessageCompleted(
        _ event: RuntimeEvent,
        pendingAssistantText: inout String
    ) -> [TimelineItem] {
        guard case let .assistantMessageCompleted(text) = event.payload else { return [] }
        // The completed event carries the full text — use it directly
        // and clear the accumulator.
        pendingAssistantText = ""
        return [TimelineItem(
            id: "assistant-\(event.id)",
            type: .assistantMessage,
            timestamp: event.timestamp,
            data: .assistantMessage(text: text)
        )]
    }

    private func handleTurnCompleted(
        _ event: RuntimeEvent,
        pendingAssistantText: inout String
    ) -> [TimelineItem] {
        var result: [TimelineItem] = []

        // Flush any accumulated assistant text that wasn't already emitted
        // by an `assistantMessageCompleted` event.
        if !pendingAssistantText.isEmpty {
            result.append(TimelineItem(
                id: "assistant-flush-\(event.id)",
                type: .assistantMessage,
                timestamp: event.timestamp,
                data: .assistantMessage(text: pendingAssistantText)
            ))
            pendingAssistantText = ""
        }

        // Emit the final-result marker.
        if case let .turnCompleted(turnID) = event.payload {
            result.append(TimelineItem(
                id: "result-\(turnID ?? event.id)",
                type: .finalResult,
                timestamp: event.timestamp,
                data: .finalResult(text: "Turn completed")
            ))
        }
        return result
    }

    private func handleTurnError(
        _ event: RuntimeEvent,
        pendingAssistantText: inout String
    ) -> [TimelineItem] {
        var result: [TimelineItem] = []

        // Flush any accumulated text before the error.
        if !pendingAssistantText.isEmpty {
            result.append(TimelineItem(
                id: "assistant-flush-\(event.id)",
                type: .assistantMessage,
                timestamp: event.timestamp,
                data: .assistantMessage(text: pendingAssistantText)
            ))
            pendingAssistantText = ""
        }

        if case let .turnError(turnID, message) = event.payload {
            result.append(TimelineItem(
                id: "error-\(turnID ?? event.id)",
                type: .error,
                timestamp: event.timestamp,
                data: .error(message: message, code: nil)
            ))
        }
        return result
    }

    // MARK: Tool calls

    private func handleToolCallRequested(_ event: RuntimeEvent) -> [TimelineItem] {
        guard case let .toolCall(name, params) = event.payload else { return [] }
        let input = params.map { dict in
            dict.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        }
        return [TimelineItem(
            id: "tool-\(event.id)",
            type: .toolCall,
            timestamp: event.timestamp,
            data: .toolCall(name: name, status: .requested, input: input, output: nil)
        )]
    }

    private func handleToolCallCompleted(_ event: RuntimeEvent) -> [TimelineItem] {
        guard case let .toolCallCompleted(name, result) = event.payload else { return [] }
        return [TimelineItem(
            id: "tool-\(event.id)",
            type: .toolCall,
            timestamp: event.timestamp,
            data: .toolCall(name: name, status: .completed, input: nil, output: result)
        )]
    }

    private func handleToolCallFailed(_ event: RuntimeEvent) -> [TimelineItem] {
        guard case let .toolCallFailed(name, error) = event.payload else { return [] }
        return [TimelineItem(
            id: "tool-\(event.id)",
            type: .toolCall,
            timestamp: event.timestamp,
            data: .toolCall(name: name, status: .failed, input: nil, output: error)
        )]
    }

    // MARK: Approval

    private func handleApprovalRequested(_ event: RuntimeEvent) -> [TimelineItem] {
        guard case let .approvalRequested(requestID, tool, command, _) = event.payload else { return [] }
        return [TimelineItem(
            id: "approval-\(requestID)",
            type: .approval,
            timestamp: event.timestamp,
            data: .approval(requestID: requestID, tool: tool, command: command, status: .pending)
        )]
    }

    private func handleApprovalResolved(_ event: RuntimeEvent) -> [TimelineItem] {
        guard case let .approvalResolved(requestID, decision) = event.payload else { return [] }
        let status: ApprovalStatus = decision == "accept" ? .accepted : .rejected
        return [TimelineItem(
            id: "approval-resolved-\(requestID)",
            type: .approval,
            timestamp: event.timestamp,
            data: .approval(requestID: requestID, tool: "", command: nil, status: status)
        )]
    }

    // MARK: File changes

    private func handleFileChange(_ event: RuntimeEvent) -> [TimelineItem] {
        guard case let .fileChange(path, changeKind) = event.payload else { return [] }
        return [TimelineItem(
            id: "file-\(event.id)",
            type: .fileChange,
            timestamp: event.timestamp,
            data: .fileChange(path: path, changeKind: changeKind)
        )]
    }

    // MARK: Global errors

    private func handleGlobalError(_ event: RuntimeEvent) -> [TimelineItem] {
        guard case let .error(message, code) = event.payload else { return [] }
        return [TimelineItem(
            id: "error-\(event.id)",
            type: .error,
            timestamp: event.timestamp,
            data: .error(message: message, code: code)
        )]
    }
}
