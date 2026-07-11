import AgentClientCore
import SwiftUI

// MARK: - Timeline View

/// Productized timeline view displaying agent execution history.
/// Supports collapsed/expanded per-item detail, run status summary,
/// file change grouping, and prominent error display.
struct TimelineView: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Timeline content
            if viewModel.timelineItems.isEmpty {
                emptyState
            } else {
                timelineContent
            }
        }
        .background(Theme.bg)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Timeline")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                Spacer()
                Text("\(viewModel.timelineItems.count) events")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }

            // Run status summary
            RunStatusSummaryView(items: viewModel.timelineItems)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
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

    // MARK: - Timeline Content

    private var timelineContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Errors first (prominent display)
                let errors = viewModel.timelineItems.filter { $0.type == .error }
                if !errors.isEmpty {
                    ErrorSectionView(errors: errors)
                    Divider()
                        .padding(.vertical, 4)
                }

                // File changes summary
                let fileChanges = viewModel.timelineItems.filter { $0.type == .fileChange }
                if !fileChanges.isEmpty {
                    FileChangesSummaryView(changes: fileChanges)
                    Divider()
                        .padding(.vertical, 4)
                }

                // All items in chronological order
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

// MARK: - Run Status Summary

/// Displays a compact summary of the run's overall status.
private struct RunStatusSummaryView: View {
    let items: [TimelineItem]

    private var hasErrors: Bool { items.contains { $0.type == .error } }
    private var hasResult: Bool { items.contains { $0.type == .finalResult } }
    private var toolCallCount: Int { items.filter { $0.type == .toolCall }.count }
    private var fileChangeCount: Int { items.filter { $0.type == .fileChange }.count }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusColor)
            }

            if toolCallCount > 0 {
                Label("\(toolCallCount) tools", systemImage: "wrench")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
            }

            if fileChangeCount > 0 {
                Label("\(fileChangeCount) files", systemImage: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
            }

            Spacer()
        }
    }

    private var statusColor: Color {
        if hasErrors { return Theme.error }
        if hasResult { return Theme.success }
        return Theme.accent
    }

    private var statusText: String {
        if hasErrors { return "Errors" }
        if hasResult { return "Completed" }
        return "Running"
    }
}

// MARK: - Error Section

/// Displays errors prominently at the top of the timeline.
private struct ErrorSectionView: View {
    let errors: [TimelineItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.error)
                Text("\(errors.count) error\(errors.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.error)
            }
            .padding(.horizontal, 16)

            ForEach(errors) { error in
                if case let .error(message, code) = error.data {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.error)
                            .lineLimit(3)
                        if let code {
                            Text(code)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.error.opacity(0.08))
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - File Changes Summary

/// Groups and summarizes file changes for quick overview.
private struct FileChangesSummaryView: View {
    let changes: [TimelineItem]
    @State private var isExpanded = false

    private var groupedChanges: [(kind: String, paths: [String])] {
        var groups: [String: [String]] = [:]
        for change in changes {
            if case let .fileChange(path, changeKind) = change.data {
                groups[changeKind, default: []].append(path)
            }
        }
        return groups.map { (kind: $0.key, paths: $0.value) }.sorted { $0.kind < $1.kind }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                    Text("\(changes.count) file change\(changes.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            if isExpanded {
                ForEach(groupedChanges, id: \.kind) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.kind.capitalized)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 16)
                            .padding(.top, 2)
                        ForEach(group.paths, id: \.self) { path in
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.fg)
                                .lineLimit(1)
                                .padding(.horizontal, 24)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Timeline Item Row

private struct TimelineItemRow: View {
    let item: TimelineItem
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

                    // Body (collapsed)
                    content

                    // Expand toggle (only for items with expandable detail)
                    if hasExpandableDetail {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isExpanded ? "Less" : "More")
                                    .font(.system(size: 10, weight: .medium))
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8))
                            }
                            .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Expanded detail
            if isExpanded {
                expandedDetail
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Expandable Detail Check

    private var hasExpandableDetail: Bool {
        switch item.data {
        case .toolCall(_, _, let input, let output):
            return (input != nil && (input?.count ?? 0) > 60) ||
                   (output != nil && (output?.count ?? 0) > 60)
        case .approval(_, _, let command, _):
            return command != nil && (command?.count ?? 0) > 60
        case .assistantMessage(let text):
            return text.count > 200
        case .userMessage(let text):
            return text.count > 200
        case .error(let message, _):
            return message.count > 100
        default:
            return false
        }
    }

    // MARK: - Expanded Detail

    @ViewBuilder
    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch item.data {
            case .toolCall(_, _, let input, let output):
                if let input {
                    detailSection(title: "Parameters", text: input)
                }
                if let output {
                    detailSection(title: "Output", text: output)
                }
            case .approval(_, _, let command, _):
                if let command {
                    detailSection(title: "Command", text: command)
                }
            case .assistantMessage(let text):
                detailSection(title: "Full message", text: text)
            case .userMessage(let text):
                detailSection(title: "Full message", text: text)
            case .error(let message, let code):
                detailSection(title: "Details", text: message)
                if let code {
                    detailSection(title: "Code", text: code)
                }
            default:
                EmptyView()
            }
        }
        .padding(8)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
    }

    private func detailSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.fg)
                .textSelection(.enabled)
        }
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

        case .toolCall(let name, let status, let input, _):
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
            }

        case .approval(_, let tool, let command, let status):
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
