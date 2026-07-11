import AgentClientCore
import SwiftUI

// MARK: - RunHistoryView (Main Entry)

/// Top-level view for browsing run history.
struct RunHistoryView: View {
    @ObservedObject var viewModel: MacShellViewModel
    @State private var selectedRunID: String?
    @State private var runs: [RunMetadata] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            RunListView(
                runs: runs,
                selectedRunID: $selectedRunID,
                isLoading: isLoading,
                errorMessage: errorMessage
            )
            .navigationTitle("Run History")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await loadRuns() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh run list")
                }
            }
        } detail: {
            if let runID = selectedRunID {
                RunDetailView(
                    runID: runID,
                    historyStore: viewModel.runHistoryStore
                )
            } else {
                Text("Select a run")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadRuns()
        }
    }

    private func loadRuns() async {
        isLoading = true
        errorMessage = nil

        do {
            let sessionID = viewModel.activeRunID
            let loaded = try viewModel.runHistoryStore.listRuns(sessionID: sessionID)
            await MainActor.run {
                runs = loaded
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - RunListView

/// Displays a list of runs with status, duration, and file count.
struct RunListView: View {
    let runs: [RunMetadata]
    @Binding var selectedRunID: String?
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading runs...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text("Error loading runs")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if runs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No runs yet")
                        .font(.headline)
                    Text("Run history will appear here")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(runs, id: \.run.id, selection: $selectedRunID) { metadata in
                    RunListRow(metadata: metadata)
                        .tag(metadata.run.id)
                }
                .listStyle(.sidebar)
            }
        }
    }
}

// MARK: - RunListRow

/// Single row in the run list showing status, duration, and file count.
struct RunListRow: View {
    let metadata: RunMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Status icon
                statusIcon
                    .font(.caption)

                // Run ID or input summary
                Text(metadata.run.input ?? metadata.run.id)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                // Duration
                if let duration = metadata.run.duration {
                    Text(formatDuration(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                // Status label
                Text(metadata.run.status.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(statusColor)

                // Runtime badge
                Text(metadata.run.runtime.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // File count (from tags if available)
                if let fileCount = metadata.tags["fileCount"] {
                    Label(fileCount, systemImage: "doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Timestamp
                if let startedAt = metadata.run.startedAt {
                    Text(startedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var statusIcon: some View {
        switch metadata.run.status {
        case .completed:
            return Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            return Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            return Image(systemName: "slash.circle")
                .foregroundStyle(.orange)
        case .running:
            return Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(.blue)
        case .waitingApproval:
            return Image(systemName: "questionmark.circle")
                .foregroundStyle(.yellow)
        case .created:
            return Image(systemName: "circle")
                .foregroundStyle(.gray)
        }
    }

    private var statusColor: Color {
        switch metadata.run.status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .cancelled:
            return .orange
        case .running:
            return .blue
        case .waitingApproval:
            return .yellow
        case .created:
            return .gray
        }
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

// MARK: - RunDetailView

/// Displays full details of a single run: metadata, timeline, files, result.
struct RunDetailView: View {
    let runID: String
    let historyStore: RunHistoryStore

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
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text("Error loading run")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        RunDetailHeader(detail: detail)

                        Divider()

                        // Metadata section
                        RunMetadataSection(detail: detail)

                        Divider()

                        // Result section
                        if let summary = detail.resultSummary {
                            RunResultSection(summary: summary)
                            Divider()
                        }

                        // Files changed section
                        if !detail.changedFiles.isEmpty {
                            RunFilesSection(files: detail.changedFiles)
                            Divider()
                        }

                        // Timeline section
                        if !detail.timeline.isEmpty {
                            RunTimelineSection(timeline: detail.timeline)
                        }
                    }
                    .padding()
                }
            } else {
                Text("Run not found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Run Details")
        .task {
            await loadDetail()
        }
    }

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil

        do {
            let loaded = try historyStore.loadRunDetail(runID: runID)
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
}

// MARK: - Run Detail Subviews

struct RunDetailHeader: View {
    let detail: RunDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Status badge
                Text(detail.metadata.run.status.rawValue.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                // Runtime badge
                Text(detail.metadata.run.runtime.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Input text
            if let input = detail.metadata.run.input {
                Text(input)
                    .font(.title2)
                    .lineLimit(3)
            }

            // Duration
            if let duration = detail.duration {
                Label(formatDuration(duration), systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusColor: Color {
        switch detail.metadata.run.status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        case .running: return .blue
        case .waitingApproval: return .yellow
        case .created: return .gray
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

struct RunMetadataSection: View {
    let detail: RunDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("Run ID")
                        .foregroundStyle(.secondary)
                    Text(detail.metadata.run.id)
                        .font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Session ID")
                        .foregroundStyle(.secondary)
                    Text(detail.metadata.sessionID)
                        .font(.system(.body, design: .monospaced))
                }
                if let startedAt = detail.metadata.run.startedAt {
                    GridRow {
                        Text("Started")
                            .foregroundStyle(.secondary)
                        Text(startedAt, style: .date)
                    }
                }
                if let finished = detail.metadata.run.finishedAt {
                    GridRow {
                        Text("Finished")
                            .foregroundStyle(.secondary)
                        Text(finished, style: .date)
                    }
                }
            }
        }
    }
}

struct RunResultSection: View {
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Result")
                .font(.headline)

            Text(summary)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct RunFilesSection: View {
    let files: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Files Changed")
                    .font(.headline)
                Spacer()
                Text("\(files.count) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(files, id: \.self) { file in
                HStack {
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                    Text(file)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct RunTimelineSection: View {
    let timeline: [TimelineItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timeline")
                .font(.headline)

            ForEach(timeline) { item in
                HStack(alignment: .top, spacing: 12) {
                    // Timeline dot
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.type.rawValue)
                            .font(.subheadline.weight(.medium))

                        // Extract text from data if available
                        timelineDetailText(item)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(item.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func timelineDetailText(_ item: TimelineItem) -> some View {
        switch item.data {
        case .userMessage(let text):
            Text(text)
        case .assistantMessage(let text):
            Text(text)
        case .thinking(let text):
            Text(text)
        case .toolCall(let name, let status, _, _):
            Text("\(name) - \(status.rawValue)")
        case .approval(_, let tool, _, let status):
            Text("\(tool) - \(status.rawValue)")
        case .fileChange(let path, let kind):
            Text("\(path) (\(kind))")
        case .error(let message, _):
            Text(message)
        case .finalResult(let text):
            Text(text)
        }
    }
}
