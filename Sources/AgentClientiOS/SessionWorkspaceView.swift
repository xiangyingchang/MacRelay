import SwiftUI
import AgentClientCore

/// Full-session workspace with toolbar, conversation stream, and bottom composer.
public struct SessionWorkspaceView: View {
    @ObservedObject var viewModel: RelayClientViewModel

    public init(viewModel: RelayClientViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Status bar
            HStack {
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

            // Session Toolbar — config pickers
            SessionToolbar(viewModel: viewModel)

            Divider()

            // Conversation stream
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if viewModel.conversationMessages.isEmpty {
                            Text("No messages yet. Send a message or connect to Mac.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding()
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

            // Bottom composer
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
    }
}

// MARK: - Session Toolbar

struct SessionToolbar: View {
    @ObservedObject var viewModel: RelayClientViewModel
    @State private var showingSessionList = false

    private let efforts = ["low", "medium", "high", "xhigh"]
    private let permissions = ["Read Only", "Default", "Full Access"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Session button — opens full list sheet
                Button {
                    showingSessionList = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.3.group")
                            .font(.caption)
                        Text(viewModel.selectedSessionID?.prefix(8) ?? "Session")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .sheet(isPresented: $showingSessionList) {
                    SessionListView(viewModel: viewModel, isPresented: $showingSessionList)
                }
                Button {
                    Task {
                        try? await viewModel.startNewSession()
                        try? await viewModel.refresh()
                    }
                } label: {
                    Label("New", systemImage: "plus.bubble")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Divider().frame(height: 20)

                // Model — driven by snapshot availableModels
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

                // Effort — snapshots may include it; otherwise show empty
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

                // Plan mode toggle
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

// MARK: - Message Bubble

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

// MARK: - Composer

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

// MARK: - Session List

struct SessionListView: View {
    @ObservedObject var viewModel: RelayClientViewModel
    @Binding var isPresented: Bool
    @State private var isLoading = false
    @State private var selectionError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter by ID, model, or status", text: $viewModel.sessionFilterText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                    if !viewModel.sessionFilterText.isEmpty {
                        Button { viewModel.sessionFilterText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Session list
                if viewModel.availableSessions.isEmpty {
                    ContentUnavailableView(
                        "No Sessions",
                        systemImage: "rectangle.3.group",
                        description: Text("Active sessions will appear here when connected to Mac.")
                    )
                } else if viewModel.filteredSessions.isEmpty {
                    ContentUnavailableView(
                        "No Matches",
                        systemImage: "magnifyingglass",
                        description: Text("No sessions match \"\(viewModel.sessionFilterText)\".")
                    )
                } else {
                    List(viewModel.filteredSessions) { session in
                        Button {
                            Task {
                                isLoading = true
                                selectionError = nil
                                do {
                                    try await viewModel.selectSession(sessionID: session.sessionID)
                                    isPresented = false
                                } catch {
                                    selectionError = error.localizedDescription
                                }
                                isLoading = false
                            }
                        } label: {
                            SessionRow(
                                session: session,
                                isSelected: session.sessionID == viewModel.selectedSessionID
                            )
                        }
                        .disabled(isLoading)
                    }
                    .listStyle(.plain)
                }

                // Error state
                if let error = selectionError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                }

                Divider()

                // Bottom bar — New Session + count
                HStack {
                    Button {
                        Task {
                            isLoading = true
                            try? await viewModel.startNewSession()
                            try? await viewModel.refresh()
                            isLoading = false
                            isPresented = false
                        }
                    } label: {
                        if isLoading {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Label("New Session", systemImage: "plus.bubble")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLoading)

                    Spacer()

                    Text("\(viewModel.availableSessions.count) session(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .navigationTitle("Sessions")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: RelaySessionInfoPayload
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                // Session ID (truncated) + model
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

                // CWD + effort + created time
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

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
        .opacity(isSelected ? 1.0 : 0.85)
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
