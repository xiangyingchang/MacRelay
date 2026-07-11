import SwiftUI
import AgentClientCore

/// Session tab root — Mac-style session list (会话 + 空间) with conversation detail.
public struct SessionWorkspaceView: View {
    @ObservedObject var viewModel: RelayClientViewModel
    @State private var navigationPath: [NavigationTarget] = []

    public init(viewModel: RelayClientViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack(path: $navigationPath) {
            SessionListContent(viewModel: viewModel, navigationPath: $navigationPath)
                .navigationDestination(for: NavigationTarget.self) { target in
                    switch target {
                    case .conversation:
                        ConversationDetailView(viewModel: viewModel, navigationPath: $navigationPath)
                    }
                }
        }
    }
}

private enum NavigationTarget: Hashable {
    case conversation
}

/// Groups workspace sessions by their workspace folder (cwd) for display.
private struct WorkspaceGroup {
    let folderName: String
    let folderPath: String
    let sessions: [RelaySessionInfoPayload]
}

// MARK: – Session List (root)

private struct SessionListContent: View {
    @ObservedObject var viewModel: RelayClientViewModel
    @Binding var navigationPath: [NavigationTarget]
    @State private var selectionError: String?
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            // Connection status bar
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.heartbeatOnline ? Color.green : .orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.connectionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isConnecting {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Divider()

            if viewModel.availableSessions.isEmpty && viewModel.workspaceSessions.isEmpty {
                emptyState
            } else {
                sessionLists
            }

            Divider()

            // Bottom bar — New Session + counts
            bottomBar
        }
        .navigationTitle("会话")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await viewModel.fetchSessions() }
    }

    // MARK: – Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No Sessions")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Active sessions will appear here\nwhen connected to Mac.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: – Session lists

    private var sessionLists: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 会话 — active sessions
                if !viewModel.availableSessions.isEmpty {
                    sectionHeader(title: "会话", count: viewModel.availableSessions.count)
                    VStack(spacing: 0) {
                        ForEach(viewModel.availableSessions) { session in
                            SessionRowView(
                                session: session,
                                isSelected: session.sessionID == viewModel.selectedSessionID,
                                isInWorkspace: false,
                                onTap: {
                                    selectAndNavigate(sessionID: session.sessionID)
                                },
                                onSave: {
                                    Task { await viewModel.saveSessionToWorkspace(sessionID: session.sessionID) }
                                },
                                onDelete: {
                                    Task { await viewModel.deleteSession(sessionID: session.sessionID) }
                                }
                            )
                            if session.sessionID != viewModel.availableSessions.last?.sessionID {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }

                // 空间 — grouped by workspace folder (cwd)
                if !viewModel.workspaceSessions.isEmpty {
                    let grouped = workspaceGroups
                    ForEach(grouped, id: \.folderName) { group in
                        workspaceSection(for: group)
                    }
                }

                if let error = selectionError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                }
            }
            .padding(.top, 8)
        }
    }

    /// Groups workspace sessions by their cwd (workspace folder path).
    private var workspaceGroups: [WorkspaceGroup] {
        let grouped = Dictionary(grouping: viewModel.workspaceSessions) { session in
            session.cwd ?? "未知空间"
        }
        return grouped.map { (folder, sessions) in
            WorkspaceGroup(folderName: folderName(from: folder), folderPath: folder, sessions: sessions)
        }.sorted { $0.folderName.localizedStandardCompare($1.folderName) == .orderedAscending }
    }

    /// Extract a human-readable folder name from a path.
    private func folderName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    @ViewBuilder
    private func workspaceSection(for group: WorkspaceGroup) -> some View {
        VStack(spacing: 0) {
            // Folder header (like Mac sidebar: folder icon + name + count)
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(group.folderName)
                    .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
                Text("(\(group.sessions.count))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)

            VStack(spacing: 0) {
                ForEach(group.sessions) { session in
                    SessionRowView(
                        session: session,
                        isSelected: session.sessionID == viewModel.selectedSessionID,
                        isInWorkspace: true,
                        onTap: {
                            selectAndNavigate(sessionID: session.sessionID)
                        },
                        onSave: nil,
                        onDelete: {
                            Task { await viewModel.deleteSession(sessionID: session.sessionID) }
                        }
                    )
                    .padding(.leading, 14) // indent under folder
                    if session.sessionID != group.sessions.last?.sessionID {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text("(\(count))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }

    // MARK: – Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    isCreating = true
                    selectionError = nil
                    do {
                        guard let newSessionID = try await viewModel.startNewSession() else {
                            selectionError = "创建新会话超时，请重试"
                            isCreating = false
                            return
                        }
                        try? await viewModel.refresh()
                        try await viewModel.selectSession(sessionID: newSessionID)
                        navigationPath.append(.conversation)
                    } catch {
                        selectionError = error.localizedDescription
                    }
                    isCreating = false
                }
            } label: {
                if isCreating {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Label("新建任务", systemImage: "plus.bubble")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isCreating)

            Spacer()

            let total = viewModel.availableSessions.count + viewModel.workspaceSessions.count
            Text("\(total) 个")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func selectAndNavigate(sessionID: String) {
        selectionError = nil
        Task {
            do {
                try await viewModel.selectSession(sessionID: sessionID)
                navigationPath.append(.conversation)
            } catch {
                selectionError = error.localizedDescription
            }
        }
    }
}

// MARK: – Session Row

private struct SessionRowView: View {
    let session: RelaySessionInfoPayload
    let isSelected: Bool
    let isInWorkspace: Bool
    let onTap: () -> Void
    let onSave: (() -> Void)?
    let onDelete: (() -> Void)?
    var body: some View {
        HStack(spacing: 10) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.displayTitle)
                        .font(.system(.subheadline, design: .monospaced))
                        .lineLimit(1)
                    if let model = session.model {
                        Text(model)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 8) {
                    if let cwd = session.cwd {
                        Label(cwd, systemImage: "folder")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    if let effort = session.effort {
                        Text("effort: \(effort)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let createdAt = session.createdAt {
                        Text(createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Checkmark for active session
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
            }

            // ⋮ menu
            Menu {
                if let onSave {
                    Button(action: onSave) {
                        Label("保存到空间", systemImage: "tray.and.arrow.down")
                    }
                }
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Label("删除", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private var statusColor: Color {
        switch session.status?.lowercased() {
        case "active", "running": return .green
        case "completed": return .blue
        case "failed", "error": return .red
        case "waiting", "waiting_on_approval": return .orange
        default: return .gray
        }
    }
}

// MARK: – Conversation Detail

private struct ConversationDetailView: View {
    @ObservedObject var viewModel: RelayClientViewModel
    @Binding var navigationPath: [NavigationTarget]

    var body: some View {
        VStack(spacing: 0) {
            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.heartbeatOnline ? Color.green : .orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.connectionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isSending {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Toolbar
            ConversationToolbar(viewModel: viewModel)
            Divider()

            // Conversation stream
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if viewModel.conversationMessages.isEmpty {
                            VStack(spacing: 8) {
                                Text("No messages yet.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 40)
                                Text("Send a message to start a conversation.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(Array(viewModel.conversationMessages.enumerated()), id: \.offset) { (i, msg) in
                                MessageBubble(message: msg)
                                    .id(i)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.conversationMessages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(max(0, viewModel.conversationMessages.count - 1), anchor: .bottom)
                    }
                }
            }

            Divider()

            // Composer
            ComposerBar(
                text: $viewModel.draftText,
                isSending: viewModel.isSending,
                isConnected: viewModel.heartbeatOnline,
                send: {
                    let text = viewModel.draftText
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    viewModel.draftText = ""
                    Task { try? await viewModel.sendTurn(text: text) }
                }
            )
        }
        .navigationTitle(viewModel.selectedSessionID?.prefix(8) ?? "会话")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: – Conversation Toolbar

private struct ConversationToolbar: View {
    @ObservedObject var viewModel: RelayClientViewModel

    private let efforts = ["low", "medium", "high", "xhigh"]
    private let permissions = ["Read Only", "Default", "Full Access"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Model
                if !viewModel.availableModels.isEmpty {
                    Picker("Model", selection: $viewModel.selectedModel) {
                        ForEach(viewModel.availableModels, id: \.self) { m in
                            Text(m).tag(m).font(.caption)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: viewModel.selectedModel) { _, _ in
                        Task { await viewModel.sendSettingsUpdate() }
                    }
                } else if !viewModel.selectedModel.isEmpty {
                    Text(viewModel.selectedModel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No model").font(.caption).foregroundStyle(.tertiary)
                }

                Divider().frame(height: 20)

                // Effort
                Picker("Effort", selection: $viewModel.selectedEffort) {
                    ForEach(efforts, id: \.self) { e in
                        Text(e.capitalized).tag(e).font(.caption)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.selectedEffort) { _, _ in
                    Task { await viewModel.sendSettingsUpdate() }
                }

                Divider().frame(height: 20)

                // Plan mode
                Toggle(isOn: $viewModel.planModeEnabled) {
                    Label("Plan", systemImage: "checklist")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .onChange(of: viewModel.planModeEnabled) { _, _ in
                    Task { await viewModel.sendSettingsUpdate() }
                }

                Divider().frame(height: 20)

                // Permission mode
                Picker("Access", selection: $viewModel.permissionMode) {
                    ForEach(permissions, id: \.self) { p in
                        Text(shortPermission(p)).tag(p).font(.caption)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.permissionMode) { _, _ in
                    Task { await viewModel.sendSettingsUpdate() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func shortPermission(_ p: String) -> String {
        switch p {
        case "Read Only": return "Read"
        case "Full Access": return "Full"
        default: return p
        }
    }
}

// MARK: – Message Bubble (unchanged)

struct MessageBubble: View {
    let message: String

    var body: some View {
        HStack {
            if message.hasPrefix("[user]") {
                Spacer()
                Text(message.replacingOccurrences(of: "[user] ", with: ""))
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: 280, alignment: .trailing)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if message.hasPrefix("[assistant]") {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                        } else if message.hasPrefix("[delta]") {
                            Circle().fill(Color.blue).frame(width: 6, height: 6)
                        } else if message.hasPrefix("[error]") {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                        }
                        Text(label(for: message))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(content(for: message))
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 280, alignment: .leading)
                Spacer()
            }
        }
    }

    private func label(for msg: String) -> String {
        if msg.hasPrefix("[user]") { return "You" }
        if msg.hasPrefix("[assistant]") { return "Codex" }
        if msg.hasPrefix("[delta]") { return "Streaming" }
        if msg.hasPrefix("[event]") { return "System" }
        if msg.hasPrefix("[status]") { return "Status" }
        if msg.hasPrefix("[model]") { return "Model" }
        if msg.hasPrefix("[error]") { return "Error" }
        return "Info"
    }

    private func content(for msg: String) -> String {
        if let range = msg.range(of: "] ") {
            return String(msg[range.upperBound...])
        }
        return msg
    }
}

// MARK: – Composer (unchanged)

struct ComposerBar: View {
    @Binding var text: String
    let isSending: Bool
    let isConnected: Bool
    let send: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 36, maxHeight: 100)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .disabled(isSending || !isConnected)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && isConnected
    }
}
