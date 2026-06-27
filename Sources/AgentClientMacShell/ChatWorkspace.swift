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
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.draftText)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 12)
                    .padding(.top, 9)
                    .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 160, alignment: .topLeading)
                if viewModel.draftText.isEmpty {
                    Text("提出后续修改要求")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 16)
                        .padding(.top, 11)
                        .allowsHitTesting(false)
                }
            }

            HStack(spacing: 12) {
                ComposerIconButton(systemName: "plus")
                SessionMenu(
                    label: "Access",
                    title: viewModel.selectedPermissionMode,
                    width: 136,
                    items: viewModel.permissions,
                    selection: $viewModel.selectedPermissionMode,
                    systemName: "shield",
                    tint: Theme.warning,
                    surface: Color.clear,
                    stroke: Color.clear,
                    onChange: viewModel.recordSettingsUpdate
                )
                Spacer()
                SessionMenu(label: "Model", title: viewModel.selectedModel, width: 176, items: viewModel.modelOptions, selection: $viewModel.selectedModel, surface: Color.clear, stroke: Color.clear, onChange: viewModel.recordSettingsUpdate)
                SessionMenu(label: "Effort", title: viewModel.selectedEffort.capitalized, width: 108, items: viewModel.efforts, selection: $viewModel.selectedEffort, systemName: "brain", surface: Color.clear, stroke: Color.clear, onChange: viewModel.recordSettingsUpdate)
                PlanToggleButton(isOn: $viewModel.planModeEnabled, onChange: viewModel.recordSettingsUpdate)
                ComposerSendButton(action: viewModel.sendDraft)
            }
            .frame(height: 40)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: 860)
        .background(Theme.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Theme.borderBright.opacity(0.78), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 36)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(Theme.canvas)
    }
}

struct ComposerIconButton: View {
    let systemName: String
    let action: () -> Void

    init(systemName: String, action: @escaping () -> Void = {}) {
        self.systemName = systemName
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 28, height: 32)
        }
        .buttonStyle(.plain)
        .help(systemName)
    }
}

struct ComposerSendButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.canvas)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .background(Theme.textSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .help("Send")
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
                Image(systemName: "switch.2")
                    .font(.system(size: 13, weight: .semibold))
                Text(isOn ? "Plan" : "Act")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isOn ? Theme.accentText : Theme.textSecondary)
            .frame(width: 86, height: 34)
        }
        .buttonStyle(.plain)
        .help(isOn ? "Plan mode" : "Act mode")
    }
}

struct SessionMenu: View {
    let label: String
    let title: String
    let width: CGFloat
    let items: [String]
    @Binding var selection: String
    let systemName: String?
    let tint: Color
    let surface: Color
    let stroke: Color
    let onChange: () -> Void

    init(
        label: String,
        title: String,
        width: CGFloat,
        items: [String],
        selection: Binding<String>,
        systemName: String? = nil,
        tint: Color = Theme.textSecondary,
        surface: Color = Theme.elevated,
        stroke: Color = Theme.borderBright,
        onChange: @escaping () -> Void
    ) {
        self.label = label
        self.title = title
        self.width = width
        self.items = items
        self._selection = selection
        self.systemName = systemName
        self.tint = tint
        self.surface = surface
        self.stroke = stroke
        self.onChange = onChange
    }

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
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Text(displayTitle)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(width: width, height: 34)
            .background(surface)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(stroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .menuStyle(.borderlessButton)
        .help("\(label): \(displayTitle)")
    }

    private var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? label : title
    }
}
