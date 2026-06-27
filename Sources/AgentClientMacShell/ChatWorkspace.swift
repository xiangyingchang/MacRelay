import AgentClientCore
import SwiftUI

struct ChatWorkspace: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if viewModel.messages.isEmpty && viewModel.pendingApproval == nil {
                            EmptyConversationView(viewModel: viewModel)
                                .padding(.top, 28)
                        } else {
                            ForEach(viewModel.messages) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }
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
                    .padding(.horizontal, 40)
                    .padding(.top, 54)
                    .padding(.bottom, 44)
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
            // Runtime status bar
            RuntimeStatusStrip(viewModel: viewModel)
            Composer(viewModel: viewModel)
        }
        .background(Theme.canvas)
    }
}

struct SessionHeader: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.activeSession.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    Text(viewModel.activeSession.subtitle.isEmpty ? viewModel.projectCWD : viewModel.activeSession.subtitle)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                    if let threadID = viewModel.runtime.currentThreadID {
                        StatusPill(text: String(threadID.prefix(8)), tone: .accent)
                    }
                }
            }
            Spacer()
            HeaderMetric(title: "Project", value: "AgentClientM1")
            HeaderMetric(title: "Mode", value: viewModel.planModeEnabled ? "Plan" : "Act")
            StatusPill(text: viewModel.sessionStatusText, tone: viewModel.sessionStatusTone)
            IconOnlyButton(systemName: "stop.circle")
            IconOnlyButton(systemName: "ellipsis")
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .background(Theme.bgPrimary)
    }
}

struct EmptyConversationView: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ready for the next change")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Ask for implementation, review, debugging, or project context. The workspace will keep session state, files, approvals, and relay status aligned.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            HStack(spacing: 10) {
                QuickPromptButton(title: "Review changes", systemName: "doc.text.magnifyingglass") {
                    viewModel.draftText = "Review the current working tree and point out bugs or missing tests."
                }
                QuickPromptButton(title: "Run checks", systemName: "checkmark.seal") {
                    viewModel.draftText = "Run the project checks and fix any failures."
                }
                QuickPromptButton(title: "Summarize state", systemName: "list.bullet.rectangle") {
                    viewModel.draftText = "Summarize the current project state and outstanding work."
                }
            }
        }
        .padding(22)
        .frame(maxWidth: 720, alignment: .leading)
        .background(Theme.bgPrimary)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct QuickPromptButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Theme.elevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
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
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.border, lineWidth: 1)
                )
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

struct RuntimeStatusStrip: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.runtime.isAppServerRunning ? Theme.success : Theme.textMuted)
                .frame(width: 6, height: 6)
            Text(viewModel.sessionStatusText)
                .fontWeight(.semibold)
            Text("·")
                .foregroundStyle(Theme.textMuted)
            if let error = viewModel.runtime.snapshot.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.warning)
                Text(error.code.map { "[\($0)]" } ?? "error")
                    .foregroundStyle(Theme.warning)
            } else {
                Text(viewModel.runtime.statusText)
            }
            Spacer()
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .padding(.horizontal, 22)
        .padding(.vertical, 7)
        .background(Theme.bgPrimary)
        .overlay(Rule(horizontal: true), alignment: .top)
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
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.draftText)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 136, alignment: .topLeading)
                    .padding(.horizontal, 12)
                    .padding(.top, 9)
                    .padding(.bottom, 8)
                if viewModel.draftText.isEmpty {
                    Text("Ask Codex to change, inspect, build, or explain")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 17)
                        .padding(.top, 18)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 7) {
                IconOnlyButton(systemName: "paperclip")
                IconOnlyButton(systemName: "mic")
                ToolbarDivider()
                HStack(spacing: 7) {
                    SessionMenu(label: "Model", title: viewModel.selectedModel, width: 144, items: viewModel.modelOptions, selection: $viewModel.selectedModel, onChange: viewModel.recordSettingsUpdate)
                    SessionMenu(label: "Effort", title: viewModel.selectedEffort.capitalized, width: 116, items: viewModel.efforts, selection: $viewModel.selectedEffort, onChange: viewModel.recordSettingsUpdate)
                    PlanToggleButton(isOn: $viewModel.planModeEnabled, onChange: viewModel.recordSettingsUpdate)
                    SessionMenu(label: "Access", title: viewModel.selectedPermissionMode, width: 152, items: viewModel.permissions, selection: $viewModel.selectedPermissionMode, onChange: viewModel.recordSettingsUpdate)
                }
                .padding(4)
                .background(Theme.canvas)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.borderBright, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(Theme.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.borderBright, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Theme.canvas)
    }
}

struct PlanToggleButton: View {
    @Binding var isOn: Bool
    let onChange: () -> Void

    var body: some View {
        Button {
            isOn.toggle()
            onChange()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .bold))
                Text(isOn ? "Plan" : "Act")
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(isOn ? Theme.accentText : Theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(width: 72, height: 30)
            .background(isOn ? Theme.accentSubtle : Theme.elevated)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isOn ? Theme.accent.opacity(0.45) : Theme.borderBright, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

struct SessionMenu: View {
    let label: String
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
                Text(label)
                    .foregroundStyle(Theme.textMuted)
                Text(title)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textMuted)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Theme.elevated)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Theme.borderBright, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .frame(width: width)
    }
}
