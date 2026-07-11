import AgentClientCore
import SwiftUI

// MARK: - Timeline View

/// Simple timeline view displaying agent execution history.
/// Renders TimelineItems in chronological order with type-specific styling.
struct TimelineView: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Timeline")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                Spacer()
                Text("\(viewModel.timelineItems.count) events")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.surface)

            Divider()

            // Timeline content
            if viewModel.timelineItems.isEmpty {
                emptyState
            } else {
                timelineList
            }
        }
        .background(Theme.bg)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(Theme.muted)
            Text("No Timeline Events")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.fg)
            Text("Run an agent task to see execution history")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Timeline List

    private var timelineList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.timelineItems) { item in
                    TimelineItemRow(item: item)
                    if item.id != viewModel.timelineItems.last?.id {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Timeline Item Row

private struct TimelineItemRow: View {
    let item: TimelineItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            icon
                .frame(width: 32, height: 32)
                .background(iconBg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Header
                HStack {
                    Text(typeName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(typeColor)
                    Spacer()
                    Text(item.timestamp, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }

                // Body
                content
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Icon

    @ViewBuilder
    private var icon: some View {
        switch item.type {
        case .userMessage:
            Image(systemName: "person.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
        case .assistantMessage:
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
        case .thinking:
            Image(systemName: "brain")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
        case .toolCall:
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.warning)
        case .approval:
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.success)
        case .fileChange:
            Image(systemName: "doc.text.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.error)
        case .finalResult:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.success)
        }
    }

    private var iconBg: Color {
        switch item.type {
        case .userMessage, .assistantMessage, .fileChange:
            return Theme.accentSoft
        case .thinking:
            return Theme.muted.opacity(0.15)
        case .toolCall:
            return Theme.warning.opacity(0.15)
        case .approval, .finalResult:
            return Theme.success.opacity(0.15)
        case .error:
            return Theme.error.opacity(0.15)
        }
    }

    // MARK: - Type Name

    private var typeName: String {
        switch item.type {
        case .userMessage: return "User"
        case .assistantMessage: return "Assistant"
        case .thinking: return "Thinking"
        case .toolCall: return "Tool Call"
        case .approval: return "Approval"
        case .fileChange: return "File Change"
        case .error: return "Error"
        case .finalResult: return "Result"
        }
    }

    private var typeColor: Color {
        switch item.type {
        case .userMessage, .assistantMessage, .fileChange:
            return Theme.accent
        case .thinking:
            return Theme.muted
        case .toolCall:
            return Theme.warning
        case .approval, .finalResult:
            return Theme.success
        case .error:
            return Theme.error
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch item.data {
        case .userMessage(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.fg)
                .lineLimit(3)

        case .assistantMessage(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.fg)
                .lineLimit(3)

        case .thinking(let text):
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .italic()
                .lineLimit(2)

        case .toolCall(let name, let status, let input, let output):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.fg)
                    StatusBadge(status: status)
                }
                if let input {
                    Text(input)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                if let output {
                    Text(output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }

        case .approval(let requestID, let tool, let command, let status):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tool)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.fg)
                    ApprovalStatusBadge(status: status)
                }
                if let command {
                    Text(command)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }

        case .fileChange(let path, let changeKind):
            HStack {
                Text(path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                Spacer()
                Text(changeKind)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.muted.opacity(0.15))
                    .clipShape(Capsule())
            }

        case .error(let message, let code):
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.error)
                    .lineLimit(3)
                if let code {
                    Text(code)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
            }

        case .finalResult(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.success)
        }
    }
}

// MARK: - Status Badges

private struct StatusBadge: View {
    let status: ToolCallStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(Capsule())
    }

    private var fg: Color {
        switch status {
        case .requested: return Theme.warning
        case .running: return Theme.accent
        case .completed: return Theme.success
        case .failed: return Theme.error
        }
    }

    private var bg: Color {
        fg.opacity(0.15)
    }
}

private struct ApprovalStatusBadge: View {
    let status: ApprovalStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(Capsule())
    }

    private var fg: Color {
        switch status {
        case .pending: return Theme.warning
        case .accepted: return Theme.success
        case .rejected: return Theme.error
        }
    }

    private var bg: Color {
        fg.opacity(0.15)
    }
}
