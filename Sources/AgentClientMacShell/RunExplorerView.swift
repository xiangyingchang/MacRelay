import AgentClientCore
import SwiftUI

// MARK: - Run Explorer View

/// Main container for browsing historical runs with list and detail panels.
struct RunExplorerView: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            explorerHeader

            Divider()

            // Content: list + detail
            HStack(spacing: 0) {
                // Left: run list
                runListPanel
                    .frame(minWidth: 280, idealWidth: 340, maxWidth: 420)

                Rule()

                // Right: detail panel
                if let selectedRun = viewModel.selectedRunForExplorer {
                    RunDetailPanel(run: selectedRun, viewModel: viewModel)
                } else {
                    emptyDetailState
                }
            }
        }
        .background(Theme.bg)
        .task {
            await viewModel.loadRunHistory()
        }
    }

    // MARK: - Header

    private var explorerHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Run Explorer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                Spacer()
                Text("\(viewModel.runHistory.count) runs")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                Button {
                    Task { await viewModel.loadRunHistory() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
                .help("Refresh run list")
            }

            RunFilterBar(filter: $viewModel.runExplorerFilter)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }

    // MARK: - Run List Panel

    private var runListPanel: some View {
        Group {
            if viewModel.isRunHistoryLoading {
                ProgressView("Loading runs...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.runHistoryError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.error)
                    Text("Error loading runs")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.fg)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredRuns.isEmpty {
                emptyListState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groupedRuns, id: \.sessionID) { group in
                            RunGroupSection(
                                group: group,
                                selectedRunID: viewModel.selectedRunForExplorer?.id,
                                onSelect: { run in viewModel.selectRunForExplorer(run) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Theme.surface)
    }

    // MARK: - Empty States

    private var emptyListState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(Theme.muted)
            Text("No Runs Found")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.fg)
            Text(viewModel.runExplorerFilter.isActive
                 ? "No runs match the current filters"
                 : "Run an agent task to see history here")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyDetailState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sidebar.right")
                .font(.system(size: 32))
                .foregroundStyle(Theme.muted)
            Text("Select a Run")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.fg)
            Text("Choose a run from the list to view details")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
    }

    // MARK: - Filtering & Grouping

    private var filteredRuns: [AgentRun] {
        viewModel.runExplorerFilter.apply(to: viewModel.runHistory)
    }

    private var groupedRuns: [RunSessionGroup] {
        let filtered = filteredRuns
        var groups: [String: [AgentRun]] = [:]
        for run in filtered {
            groups[run.sessionID, default: []].append(run)
        }
        return groups
            .map { RunSessionGroup(sessionID: $0.key, runs: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { ($0.runs.first?.createdAt ?? .distantPast) > ($1.runs.first?.createdAt ?? .distantPast) }
    }
}

// MARK: - Run Session Group

private struct RunSessionGroup: Identifiable {
    let id = UUID()
    let sessionID: String
    let runs: [AgentRun]

    var displayTitle: String {
        if sessionID.isEmpty { return "Unknown Session" }
        return sessionID
    }
}

// MARK: - Run Group Section

private struct RunGroupSection: View {
    let group: RunSessionGroup
    let selectedRunID: String?
    let onSelect: (AgentRun) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                Text(group.displayTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Text("(\(group.runs.count))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted.opacity(0.6))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            // Runs
            ForEach(group.runs) { run in
                RunRow(
                    run: run,
                    isSelected: run.id == selectedRunID,
                    action: { onSelect(run) }
                )
                .padding(.horizontal, 8)
            }
        }
    }
}

// MARK: - Run Row

private struct RunRow: View {
    let run: AgentRun
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                // Title row
                HStack(spacing: 8) {
                    RunStatusIndicator(status: run.status)
                    Text(run.input ?? run.id)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                    Spacer()
                }

                // Info row
                HStack(spacing: 10) {
                    // Status label
                    RunStatusBadge(status: run.status)

                    // Runtime
                    if run.runtime != .local {
                        Text(run.runtime.providerName)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.muted.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    // Model
                    if let model = run.model, !model.isEmpty {
                        Text(model)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Files changed
                    if run.filesChangedCount > 0 {
                        Label("\(run.filesChangedCount)", systemImage: "doc.text")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                    }
                }

                // Time row
                HStack(spacing: 8) {
                    Text(run.createdAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)

                    if let duration = run.duration {
                        Text(formatDuration(duration))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }

                    Spacer()

                    // Error indicator
                    if run.status == .failed, let error = run.errorSummary ?? run.resultSummary {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.error)
                            .help(error)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Theme.accent.opacity(0.12) : (isHovering ? Theme.sidebarHover : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSm)
                .stroke(isSelected ? Theme.accent.opacity(0.28) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        .onHover { hovering in isHovering = hovering }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.0fs", duration)
        } else if duration < 3600 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m\(seconds)s"
        } else {
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            return "\(hours)h\(minutes)m"
        }
    }
}

// MARK: - Run Status Indicator (dot)

private struct RunStatusIndicator: View {
    let status: RunStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch status {
        case .completed: return Theme.success
        case .failed: return Theme.error
        case .cancelled: return Theme.warning
        case .running: return Theme.accent
        case .waitingApproval: return Theme.warning
        case .created: return Theme.muted
        case .interrupted: return Theme.warning
        }
    }
}

// MARK: - Run Status Badge

private struct RunStatusBadge: View {
    let status: RunStatus

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(fg.opacity(0.15))
            .clipShape(Capsule())
    }

    private var fg: Color {
        switch status {
        case .completed: return Theme.success
        case .failed: return Theme.error
        case .cancelled: return Theme.warning
        case .running: return Theme.accent
        case .waitingApproval: return Theme.warning
        case .created: return Theme.muted
        case .interrupted: return Theme.warning
        }
    }

    private var label: String {
        switch status {
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .running: return "Running"
        case .waitingApproval: return "Waiting"
        case .created: return "Created"
        case .interrupted: return "Interrupted"
        }
    }
}

// MARK: - Run Filter Bar

private struct RunFilterBar: View {
    @Binding var filter: RunExplorerFilter

    var body: some View {
        HStack(spacing: 12) {
            // Status filter
            HStack(spacing: 4) {
                Text("Status")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Menu {
                    ForEach(RunExplorerFilter.StatusOption.allCases, id: \.self) { option in
                        Button {
                            filter.statusOption = option
                        } label: {
                            HStack {
                                Text(option.label)
                                if filter.statusOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(filter.statusOption.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(filter.statusOption == .all ? Theme.muted : Theme.accent)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSm)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Runtime filter
            HStack(spacing: 4) {
                Text("Runtime")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Menu {
                    ForEach(RunExplorerFilter.RuntimeOption.allCases, id: \.self) { option in
                        Button {
                            filter.runtimeOption = option
                        } label: {
                            HStack {
                                Text(option.label)
                                if filter.runtimeOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(filter.runtimeOption.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(filter.runtimeOption == .all ? Theme.muted : Theme.accent)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSm)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer()

            // Reset button
            if filter.isActive {
                Button {
                    filter = RunExplorerFilter()
                } label: {
                    Text("Reset")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Run Detail Panel

private struct RunDetailPanel: View {
    let run: AgentRun
    @ObservedObject var viewModel: MacShellViewModel
    @State private var detail: RunDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading run details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.error)
                    Text("Error loading run")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.fg)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header with status and input
                        detailHeader

                        Divider()

                        // Metadata grid
                        RunDetailMetadataGrid(run: run)

                        Divider()

                        // Result or error
                        if let summary = run.errorSummary ?? run.resultSummary {
                            RunDetailResultSection(
                                summary: summary,
                                isError: run.status == .failed
                            )
                            Divider()
                        }

                        // Files changed
                        if let detail, !detail.changedFiles.isEmpty {
                            RunDetailFilesSection(files: detail.changedFiles)
                            Divider()
                        }

                        // Approval history
                        if run.approvalCount > 0 {
                            RunDetailApprovalSection(count: run.approvalCount)
                            Divider()
                        }

                        // Timeline (reuse existing TimelineView pattern)
                        if let detail, !detail.timeline.isEmpty {
                            RunDetailTimelineSection(timeline: detail.timeline)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Theme.bg)
        .task {
            await loadDetail()
        }
        .onChange(of: run.id) { _ in
            Task { await loadDetail() }
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                RunStatusBadge(status: run.status)
                Spacer()
                Text(run.runtime.providerName)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.accentSoft)
                    .clipShape(Capsule())
            }

            if let input = run.input {
                Text(input)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(4)
            }

            if let duration = run.duration {
                Label(formatDuration(duration), systemImage: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: - Loading

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try viewModel.runHistoryStore.loadRunDetail(runID: run.id)
            await MainActor.run {
                detail = loaded
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else if duration < 3600 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Detail Metadata Grid

private struct RunDetailMetadataGrid: View {
    let run: AgentRun

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.muted)
                .textCase(.uppercase)
                .tracking(0.6)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                metadataRow("Run ID", run.id)
                metadataRow("Session", run.sessionID)
                metadataRow("Runtime", run.runtime.providerName)
                if let provider = run.provider {
                    metadataRow("Provider", provider)
                }
                if let model = run.model {
                    metadataRow("Model", model)
                }
                if let startedAt = run.startedAt {
                    GridRow {
                        Text("Started")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 72, alignment: .leading)
                        Text(startedAt, style: .date)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.fg)
                        Text(startedAt, style: .time)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.fg)
                    }
                }
                if let finishedAt = run.finishedAt {
                    GridRow {
                        Text("Finished")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 72, alignment: .leading)
                        Text(finishedAt, style: .date)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.fg)
                        Text(finishedAt, style: .time)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.fg)
                    }
                }
                if run.filesChangedCount > 0 {
                    metadataRow("Files", "\(run.filesChangedCount)")
                }
                if run.toolCallCount > 0 {
                    metadataRow("Tools", "\(run.toolCallCount)")
                }
                if run.approvalCount > 0 {
                    metadataRow("Approvals", "\(run.approvalCount)")
                }
            }
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.fg)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Detail Result Section

private struct RunDetailResultSection: View {
    let summary: String
    let isError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isError ? Theme.error : Theme.success)
                Text(isError ? "Error" : "Result")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isError ? Theme.error : Theme.success)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }

            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(isError ? Theme.error : Theme.fg)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((isError ? Theme.error : Theme.success).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        }
    }
}

// MARK: - Detail Files Section

private struct RunDetailFilesSection: View {
    let files: [String]
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                    Text("\(files.count) File\(files.count == 1 ? "" : "s") Changed")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(files, id: \.self) { file in
                    HStack(spacing: 8) {
                        Image(systemName: "doc")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                        Text(file)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.fg)
                            .lineLimit(1)
                            .textSelection(.enabled)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                }
            }
        }
    }
}

// MARK: - Detail Approval Section

private struct RunDetailApprovalSection: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.success)
            Text("\(count) Approval\(count == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.success)
                .textCase(.uppercase)
                .tracking(0.6)
            Spacer()
        }
    }
}

// MARK: - Detail Timeline Section

private struct RunDetailTimelineSection: View {
    let timeline: [TimelineItem]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                    Text("Timeline (\(timeline.count) events)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVStack(spacing: 0) {
                    ForEach(timeline) { item in
                        RunTimelineItemRow(item: item)
                        if item.id != timeline.last?.id {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            }
        }
    }
}

// MARK: - Timeline Item Row (compact for detail panel)

private struct RunTimelineItemRow: View {
    let item: TimelineItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            icon
                .frame(width: 28, height: 28)
                .background(iconBg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(typeName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(typeColor)
                    Spacer()
                    Text(item.timestamp, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }

                content
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var icon: some View {
        switch item.type {
        case .userMessage:
            Image(systemName: "person.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
        case .assistantMessage:
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
        case .thinking:
            Image(systemName: "brain")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        case .toolCall:
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.warning)
        case .approval:
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.success)
        case .fileChange:
            Image(systemName: "doc.text.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.error)
        case .finalResult:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
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

    @ViewBuilder
    private var content: some View {
        switch item.data {
        case .userMessage(let text):
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.fg)
                .lineLimit(2)

        case .assistantMessage(let text):
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.fg)
                .lineLimit(2)

        case .thinking(let text):
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(Theme.muted)
                .italic()
                .lineLimit(1)

        case .toolCall(let name, let status, _, _):
            HStack(spacing: 6) {
                Text(name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.fg)
                RunTimelineStatusBadge(status: status)
            }

        case .approval(_, let tool, _, let status):
            HStack(spacing: 6) {
                Text(tool)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.fg)
                RunTimelineApprovalBadge(status: status)
            }

        case .fileChange(let path, _):
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.fg)
                .lineLimit(1)

        case .error(let message, _):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.error)
                .lineLimit(2)

        case .finalResult(let text):
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.success)
                .lineLimit(2)
        }
    }
}

// MARK: - Timeline Status Badges (compact)

private struct RunTimelineStatusBadge: View {
    let status: ToolCallStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(fg.opacity(0.15))
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
}

private struct RunTimelineApprovalBadge: View {
    let status: ApprovalStatus

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(fg.opacity(0.15))
            .clipShape(Capsule())
    }

    private var fg: Color {
        switch status {
        case .pending: return Theme.warning
        case .accepted: return Theme.success
        case .rejected: return Theme.error
        }
    }
}

// MARK: - Run Explorer Filter Model

/// Filter state for the Run Explorer.
struct RunExplorerFilter {
    enum StatusOption: String, CaseIterable {
        case all
        case running
        case completed
        case failed
        case interrupted

        var label: String {
            switch self {
            case .all: return "All"
            case .running: return "Running"
            case .completed: return "Completed"
            case .failed: return "Failed"
            case .interrupted: return "Interrupted"
            }
        }
    }

    enum RuntimeOption: String, CaseIterable {
        case all
        case codex
        case claude
        case api

        var label: String {
            switch self {
            case .all: return "All"
            case .codex: return "Codex"
            case .claude: return "Claude"
            case .api: return "API"
            }
        }
    }

    var statusOption: StatusOption = .all
    var runtimeOption: RuntimeOption = .all

    var isActive: Bool {
        statusOption != .all || runtimeOption != .all
    }

    func apply(to runs: [AgentRun]) -> [AgentRun] {
        runs.filter { run in
            matchesStatus(run) && matchesRuntime(run)
        }
    }

    private func matchesStatus(_ run: AgentRun) -> Bool {
        switch statusOption {
        case .all: return true
        case .running: return run.status == .running || run.status == .waitingApproval || run.status == .created
        case .completed: return run.status == .completed
        case .failed: return run.status == .failed
        case .interrupted: return run.status == .interrupted || run.status == .cancelled
        }
    }

    private func matchesRuntime(_ run: AgentRun) -> Bool {
        switch runtimeOption {
        case .all: return true
        case .codex: return run.runtime == .codex
        case .claude: return run.runtime == .claudeCode || run.runtime == .anthropic
        case .api: return run.runtime == .openAI || run.runtime == .deepSeek || run.runtime == .mimo || run.runtime == .gemini
        }
    }
}
