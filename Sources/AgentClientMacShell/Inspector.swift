import SwiftUI

struct Inspector: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Session Inspector")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                StatusPill(text: "Local", tone: .success)
            }

            InspectorSection(title: "Changed Files") {
                VStack(spacing: 8) {
                    if viewModel.displayFiles.isEmpty {
                        EmptyFilesView(runtimeMode: viewModel.runtimeMode)
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

            InspectorSection(title: "Diff Preview") {
                if let file = viewModel.selectedDisplayFile {
                    DiffPreview(file: file)
                } else {
                    EmptyDiffView()
                }
            }

            InspectorSection(title: "Session") {
                VStack(spacing: 8) {
                    if viewModel.runtimeMode == .real, let settings = viewModel.runtime.snapshot.settings {
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

            InspectorSection(title: "Codex Runtime") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatusPill(
                            text: viewModel.runtime.detection.isInstalled ? "Installed" : "Missing",
                            tone: viewModel.runtimeStatusTone
                        )
                        StatusPill(
                            text: viewModel.runtimeMode.rawValue,
                            tone: viewModel.runtimeMode == .real ? .accent : .warning
                        )
                        Spacer()
                        Text(viewModel.runtime.detection.version ?? viewModel.runtime.detection.executablePath ?? "Not found")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                    }
                    Text(viewModel.runtime.statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                    if !viewModel.runtime.modelNames.isEmpty {
                        Text(viewModel.runtime.modelNames.prefix(3).joined(separator: " / "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.accentText)
                            .lineLimit(1)
                    }
                    if !viewModel.runtime.rateLimitText.isEmpty {
                        Text(viewModel.runtime.rateLimitText)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        FileActionButton(title: "Detect", systemName: "magnifyingglass", action: viewModel.refreshCodexDetection)
                        FileActionButton(title: "Init", systemName: "bolt", action: viewModel.requestRuntimeInitializeAndModels)
                        FileActionButton(title: "Stop", systemName: "stop", role: .destructive, action: viewModel.stopRuntime)
                        Spacer()
                    }
                }
                .padding(9)
                .background(Theme.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            InspectorSection(title: "Pairing") {
                VStack(alignment: .leading, spacing: 8) {
                    #if os(macOS)
                    if let qrImage = viewModel.relayPairingQRImage {
                        Image(nsImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 120, height: 120)
                    }
                    #endif
                    Text(viewModel.relayPairingDisplay)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                    HStack {
                        FileActionButton(title: "Rotate", systemName: "arrow.triangle.2.circlepath", action: viewModel.rotateRelayPairing)
                        Spacer()
                    }
                }
                .padding(9)
                .background(Theme.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            InspectorSection(title: "Mac Relay") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        StatusPill(
                            text: viewModel.relayServerRunning ? "Running" : "Stopped",
                            tone: viewModel.relayServerRunning ? .success : .warning
                        )
                        if viewModel.relayServerRunning {
                            StatusPill(text: "\(viewModel.relayServerHost):\(viewModel.relayServerPort)", tone: .accent)
                        }
                        Spacer()
                        StatusPill(text: "Seq \(viewModel.relaySnapshot.lastEventSeq)", tone: .success)
                    }
                    if let error = viewModel.relayServerLastError {
                        Text("Error: \(error)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.error)
                            .lineLimit(2)
                    }
                    HStack {
                        Text("Host mode:").font(.system(size: 11))
                        Picker("Host mode", selection: Binding(
                            get: { viewModel.relayHostMode },
                            set: { viewModel.setRelayHost(mode: $0) }
                        )) {
                            Text("Localhost").tag("local")
                            Text("LAN").tag("lan")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Spacer()
                    }
                    if viewModel.relayHostMode == "lan", viewModel.relayLANIPv4 == nil {
                        Text("⚠️ No LAN IP found — using localhost")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    KeyValue("Host", viewModel.relayServerHost)
                    KeyValue("Port", viewModel.relayServerRunning ? "\(viewModel.relayServerPort)" : "-")
                    KeyValue("Auto-start", viewModel.relayServerConfiguredToStart ? "Enabled" : "Disabled")
                    KeyValue("Session", viewModel.relaySnapshot.activeSessionID ?? "-")
                    KeyValue("Status", viewModel.relaySnapshot.session?.status ?? "-")
                    KeyValue("Pending", "\(viewModel.relaySnapshot.pendingApprovals.filter(\.isPending).count)")
                    Text(viewModel.relayStatusText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
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
                .padding(9)
                .background(Theme.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            InspectorSection(title: "Mock Commands") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.commandLog) { action in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.type.rawValue)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.accentText)
                            Text(action.detail)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.textMuted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(9)
                .background(Theme.codeBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(18)
        .background(Theme.bgSecondary)
        }
    }
}

struct EmptyFilesView: View {
    let runtimeMode: RuntimeMode

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(Theme.textMuted)
            Text(runtimeMode == .real ? "No file changes in this session" : "No changed files")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Spacer()
        }
        .padding(10)
        .background(Theme.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

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
                        .foregroundStyle(Theme.textMuted)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(compactPath(file.path))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            StatusPill(text: file.status, tone: .accent)
                            Text(file.impact)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textMuted)
                            Spacer()
                            Text(file.reviewState)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(file.reviewState == "Discarded" ? Theme.error : Theme.textMuted)
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
        .background(isActive ? Theme.accentSubtle : Theme.bgTertiary)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Theme.accent.opacity(0.45) : Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func compactPath(_ path: String) -> String {
        let parts = path.split(separator: "/")
        guard parts.count > 2 else { return path }
        return parts.suffix(2).joined(separator: "/")
    }
}

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
            .foregroundStyle(role == .destructive ? Theme.error : Theme.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Theme.borderBright, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct DiffPreview: View {
    let file: ChangedFileMock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(file.path)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            VStack(alignment: .leading, spacing: 5) {
                DiffLine(prefix: "-", text: "ToolbarChip(text: \"Codex\")", color: Theme.error)
                DiffLine(prefix: "+", text: "ActiveSessionsBar(viewModel: viewModel)", color: Theme.success)
                DiffLine(prefix: "+", text: "Composer toolbar carries session controls", color: Theme.success)
                DiffLine(prefix: " ", text: "Diff and approval remain session-scoped", color: Theme.textMuted)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.codeBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct EmptyDiffView: View {
    var body: some View {
        Text("No diff available")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Theme.codeBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

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
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .font(.system(size: 11, design: .monospaced))
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(title.uppercased())
            content
        }
    }
}
