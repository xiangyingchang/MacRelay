import AgentClientCore
import SwiftUI

struct ChatWorkspace: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        VStack(spacing: 0) {
            SessionHeader(viewModel: viewModel)
            Rule(horizontal: true)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(viewModel.messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                        if let approval = viewModel.pendingApproval {
                            CommandApprovalCard(
                                approval: approval,
                                approve: viewModel.approveCommand,
                                discard: viewModel.discardCommand
                            )
                            .id("pending-approval")
                        }
                    }
                    .padding(.horizontal, 34)
                    .padding(.top, 22)
                    .padding(.bottom, 38)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: viewModel.messages.last?.id) { _, newID in
                    guard let newID else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(newID, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.messages.last?.text) { _, _ in
                    guard let lastID = viewModel.messages.last?.id else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            // Runtime status bar — always visible in real mode
            if viewModel.runtimeMode == .real {
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.runtime.isAppServerRunning ? Theme.success : Theme.textMuted)
                        .frame(width: 6, height: 6)
                    Text(viewModel.realSessionStatusText)
                        .fontWeight(.semibold)
                    if let error = viewModel.runtime.snapshot.lastError {
                        Text("·")
                            .foregroundStyle(Theme.textMuted)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.warning)
                        Text(error.code.map { "[\($0)]" } ?? "error")
                            .foregroundStyle(Theme.warning)
                    } else {
                        Text("·")
                            .foregroundStyle(Theme.textMuted)
                        Text(viewModel.runtime.statusText)
                    }
                    Spacer()
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .background(Theme.bgTertiary)
            }
            Rule(horizontal: true)
            Composer(viewModel: viewModel)
        }
        .background(Theme.bgPrimary)
    }
}

struct SessionHeader: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.activeSession.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(viewModel.activeSession.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            HeaderMetric(title: "Project", value: "AgentClientM1")
            HeaderMetric(title: "Mode", value: viewModel.planModeEnabled ? "Plan" : "Act")
            if viewModel.runtimeMode == .real {
                StatusPill(text: viewModel.realSessionStatusText, tone: viewModel.realSessionStatusTone)
            } else {
                StatusPill(text: viewModel.activeSession.status.capitalized, tone: viewModel.activeSession.status == "waiting" ? .warning : .accent)
            }
            IconOnlyButton(systemName: "stop.circle")
            IconOnlyButton(systemName: "ellipsis")
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
        .background(Theme.bgPrimary)
    }
}

struct MessageRow: View {
    let message: ConversationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == "User" {
                Spacer(minLength: 110)
                Text(message.text)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Theme.userBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: 640, alignment: .trailing)
            } else {
                RoleBadge(role: message.role)
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.role)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(roleColor)
                    Text(message.text)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(message.role == "Tool" ? Theme.codeBg : Theme.agentBubble)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 720, alignment: .leading)
                Spacer(minLength: 90)
            }
        }
    }

    var roleColor: Color {
        message.role == "Tool" ? Theme.warning : Theme.accentText
    }
}

struct CommandApprovalCard: View {
    let approval: RelayApprovalPayload
    let approve: () -> Void
    let discard: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoleBadge(role: "Approval")
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("Approval required", systemImage: "lock.open")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    StatusPill(text: "Pending", tone: .warning)
                }
                Text(approval.reason ?? approval.method)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Text(approval.command ?? "-")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.codeBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 8) {
                    Button(action: approve) {
                        Label("Approve", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    Button(role: .destructive, action: discard) {
                        Label("Discard", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
                .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: 720, alignment: .leading)
            .background(Theme.warningBg)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.warning.opacity(0.28), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 90)
        }
    }
}

struct Composer: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                if viewModel.draftText.isEmpty {
                    Text("Ask Codex to change, inspect, build, or explain...")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)  // don't block TextEditor focus
                }
                TextEditor(text: $viewModel.draftText)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.clear)
            }
            .frame(minHeight: 56)  // allow expansion
            .frame(maxHeight: 120)
            .background(Theme.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.borderBright, lineWidth: 1)
            )

            HStack(spacing: 7) {
                IconOnlyButton(systemName: "paperclip")
                IconOnlyButton(systemName: "mic")
                ToolbarDivider()
                SessionMenu(
                    title: viewModel.runtimeMode.rawValue,
                    width: 68,
                    items: RuntimeMode.allCases.map(\.rawValue),
                    selection: Binding(
                        get: { viewModel.runtimeMode.rawValue },
                        set: { viewModel.runtimeMode = RuntimeMode(rawValue: $0) ?? .mock }
                    ),
                    onChange: {}
                )
                ToolbarDivider()
                SessionMenu(title: viewModel.selectedModel, width: 98, items: viewModel.modelOptions, selection: $viewModel.selectedModel, onChange: viewModel.recordSettingsUpdate)
                SessionMenu(title: viewModel.selectedEffort.capitalized, width: 78, items: viewModel.efforts, selection: $viewModel.selectedEffort, onChange: viewModel.recordSettingsUpdate)
                Toggle(isOn: $viewModel.planModeEnabled) {
                    Label("Plan", systemImage: "checklist")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .onChange(of: viewModel.planModeEnabled) { _, _ in viewModel.recordSettingsUpdate() }
                SessionMenu(title: viewModel.selectedPermissionMode, width: 124, items: viewModel.permissions, selection: $viewModel.selectedPermissionMode, onChange: viewModel.recordSettingsUpdate)
                IconOnlyButton(systemName: "folder")
                Spacer()
                Button(action: viewModel.sendDraft) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .background(Theme.bgPrimary)
    }
}

struct SessionMenu: View {
    let title: String
    let width: CGFloat
    let items: [String]
    @Binding var selection: String
    let onChange: () -> Void

    var body: some View {
        Menu {
            ForEach(items, id: \.self) { item in
                Button(item) {
                    selection = item
                    onChange()
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Theme.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .frame(width: width)
    }
}
