import AgentClientCore
import SwiftUI

struct SettingsWorkspace: View {
    @ObservedObject var viewModel: MacShellViewModel
    @State private var filesExpanded = false
    @State private var diffExpanded = false
    @State private var sessionExpanded = false
    @State private var runtimeExpanded = false
    @State private var relayExpanded = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Settings")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.fg)
                        Spacer()
                        StatusPill(text: "Local", tone: .success)
                    }
                    HStack(spacing: 8) {
                        InspectorStat(title: "State", value: viewModel.sessionStatusText, tone: viewModel.sessionStatusTone)
                        InspectorStat(title: "Relay", value: viewModel.relayServerRunning ? "Online" : "Off", tone: viewModel.relayServerRunning ? .success : .warning)
                        InspectorStat(title: "Files", value: "\(viewModel.displayFiles.count)", tone: .accent)
                    }
                }

                // Files section
                CollapsibleSection(title: "Changed Files", badge: "\(viewModel.displayFiles.count)", isExpanded: $filesExpanded) {
                    VStack(spacing: 8) {
                        if viewModel.displayFiles.isEmpty {
                            EmptyFilesView()
                        } else {
                            ForEach(viewModel.displayFiles) { file in
                                FileRow(
                                    file: file,
                                    isActive: file.id == viewModel.selectedDisplayFile?.id,
                                    select: { viewModel.selectedFileID = file.id },
                                    approve: { viewModel.approveFile(file.id) },
                                    discard: { viewModel.discardFile(file.id) }
                                )
                            }
                        }
                    }
                }

                // Diff section
                CollapsibleSection(title: "Diff Preview", isExpanded: $diffExpanded) {
                    if let file = viewModel.selectedDisplayFile {
                        DiffPreview(file: file)
                    } else {
                        EmptyDiffView()
                    }
                }

                // Session section
                CollapsibleSection(title: "Session", isExpanded: $sessionExpanded) {
                    VStack(spacing: 8) {
                        if let settings = viewModel.runtime.snapshot.settings {
                            KeyValue("Model", settings.model ?? viewModel.selectedModel)
                            KeyValue("Effort", settings.effort ?? viewModel.selectedEffort)
                            KeyValue("Approval", settings.approvalPolicy ?? "-")
                            KeyValue("Sandbox", settings.sandboxType ?? "-")
                            KeyValue("CWD", settings.cwd ?? viewModel.projectCWD)
                            KeyValue("Status", viewModel.runtime.snapshot.status.rawValue)
                        } else {
                            KeyValue("Model", viewModel.selectedModel)
                            KeyValue("Effort", viewModel.selectedEffort)
                            KeyValue("Mode", viewModel.planModeEnabled ? "Plan" : "Act")
                            KeyValue("Access", viewModel.selectedPermissionMode)
                            KeyValue("CWD", viewModel.projectCWD)
                        }
                    }
                }

                // Codex Runtime section
                CollapsibleSection(title: "Codex Runtime", isExpanded: $runtimeExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            StatusPill(
                                text: viewModel.runtime.cliInstalled ? "Installed" : "Missing",
                                tone: viewModel.runtimeStatusTone
                            )
                            Spacer()
                            Text(viewModel.runtime.statusText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                        Text(viewModel.runtime.statusText)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(2)
                        if !viewModel.runtime.modelNames.isEmpty {
                            Text(viewModel.runtime.modelNames.prefix(3).joined(separator: " / "))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                        }
                        if !viewModel.runtime.rateLimitText.isEmpty {
                            Text(viewModel.runtime.rateLimitText)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(2)
                        }
                        HStack(spacing: 8) {
                            FileActionButton(title: "Detect", systemName: "magnifyingglass", action: viewModel.refreshCodexDetection)
                            FileActionButton(title: "Init", systemName: "bolt", action: viewModel.requestRuntimeInitializeAndModels)
                            FileActionButton(title: "Stop", systemName: "stop", role: .destructive, action: viewModel.stopRuntime)
                            Spacer()
                        }
                    }
                }

                // Relay section
                CollapsibleSection(title: "Mac Relay", isExpanded: $relayExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            StatusPill(text: viewModel.relayServerRunning ? "Running" : "Stopped", tone: viewModel.relayServerRunning ? .success : .warning)
                            if viewModel.relayServerRunning {
                                StatusPill(text: "\(viewModel.relayServerHost):\(viewModel.relayServerPort)", tone: .accent)
                            }
                            Spacer()
                            StatusPill(text: "Seq \(viewModel.relaySnapshot.lastEventSeq)", tone: .success)
                        }
                        if let error = viewModel.relayServerLastError {
                            Text("Error: \(error)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.error).lineLimit(2)
                        }
                        KeyValue("Host", viewModel.relayServerHost)
                        KeyValue("Port", viewModel.relayServerRunning ? "\(viewModel.relayServerPort)" : "-")
                        KeyValue("Auto-start", viewModel.relayServerConfiguredToStart ? "Enabled" : "Disabled")
                        KeyValue("Session", viewModel.relaySnapshot.activeSessionID ?? "-")
                        KeyValue("Status", viewModel.relaySnapshot.session?.status ?? "-")
                        KeyValue("Pending", "\(viewModel.relaySnapshot.pendingApprovals.filter(\.isPending).count)")
                        Text(viewModel.relayStatusText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.muted).lineLimit(1)
                        HStack {
                            if viewModel.relayServerRunning {
                                FileActionButton(title: "Stop", systemName: "stop", role: .destructive, action: viewModel.stopRelayServer)
                            } else {
                                FileActionButton(title: "Start", systemName: "play", action: { viewModel.startRelayServer() })
                            }
                            FileActionButton(title: "Snapshot", systemName: "arrow.clockwise", action: viewModel.requestRelaySnapshot)
                            Spacer()
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.sidebarBg)
    }
}

// MARK: - Collapsible Section
struct CollapsibleSection<Content: View>: View {
    let title: String
    var badge: String?
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 12)
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.muted)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 6)
                            .frame(height: 18)
                            .background(Theme.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusSm)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .padding(10)
                    .background(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusSm)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Inspector Stat
struct InspectorStat: View {
    let title: String
    let value: String
    let tone: StatusPill.Tone

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.muted)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSm)
                .stroke(color.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
    }

    private var color: Color {
        switch tone {
        case .accent:  Theme.accent
        case .success: Theme.success
        case .warning: Theme.warning
        case .info:    Theme.fg
        case .passive: Theme.muted
        }
    }
}

// MARK: - File Row
struct FileRow: View {
    let file: ChangedFileMock
    let isActive: Bool
    let select: () -> Void
    let approve: () -> Void
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: select) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Theme.muted)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(compactPath(file.path))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.fg)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            StatusPill(text: file.status, tone: .accent)
                            Text(file.impact)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                            Spacer()
                            Text(file.reviewState)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(file.reviewState == "Discarded" ? Theme.error : Theme.muted)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                FileActionButton(title: "Approve", systemName: "checkmark", action: approve)
                FileActionButton(title: "Discard", systemName: "xmark", role: .destructive, action: discard)
                Spacer()
            }
        }
        .padding(10)
        .background(isActive ? Theme.accentSoft : Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSm)
                .stroke(isActive ? Theme.accent.opacity(0.45) : Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
    }

    private func compactPath(_ path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > 2 else { return path }
        return parts.suffix(2).joined(separator: "/")
    }
}

// MARK: - Empty Files View
struct EmptyFilesView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(Theme.muted)
            Text("No file changes in this session")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .padding(10)
        .background(Theme.sidebarHover)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
    }
}

// MARK: - Diff Preview
struct DiffPreview: View {
    let file: ChangedFileMock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(file.path)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 5) {
                DiffLine(prefix: "-", text: "ToolbarChip(text: \"Codex\")", color: Theme.error)
                DiffLine(prefix: "+", text: "ActiveSessionsBar(viewModel: viewModel)", color: Theme.success)
                DiffLine(prefix: "+", text: "Composer toolbar carries session controls", color: Theme.success)
                DiffLine(prefix: " ", text: "Diff and approval remain session-scoped", color: Theme.muted)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        }
    }
}

// MARK: - Empty Diff View
struct EmptyDiffView: View {
    var body: some View {
        Text("No diff available")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
    }
}

// MARK: - Diff Line
struct DiffLine: View {
    let prefix: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(prefix)
                .foregroundStyle(color)
                .frame(width: 12, alignment: .leading)
            Text(text)
                .foregroundStyle(Theme.fg)
                .lineLimit(1)
        }
        .font(.system(size: 11, design: .monospaced))
    }
}

// MARK: - File Action Button
struct FileActionButton: View {
    let title: String
    let systemName: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(role == .destructive ? Theme.error : Theme.muted)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Theme.sidebarBg)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
