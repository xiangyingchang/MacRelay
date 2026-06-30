import AgentClientCore
import SwiftUI

// MARK: - Chat Workspace
struct ChatWorkspace: View {
    @ObservedObject var viewModel: MacShellViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if viewModel.messages.isEmpty && viewModel.pendingApproval == nil {
                            EmptyConversationView()
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
            // Composer
            Composer(viewModel: viewModel)
        }
        .background(Theme.bg)
    }
}

// MARK: - Empty State
struct EmptyConversationView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("说说你在想什么")
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Message Row
struct MessageRow: View {
    let message: ConversationMessage
    private var isUser: Bool { message.role == "User" }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MessageAvatar(role: message.role)
            Group {
                if isUser {
                    userMessageContent
                } else {
                    agentMessageContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, isUser ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var userMessageContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            messageRoleLabel
                .foregroundStyle(Theme.accent)
            Text(message.text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.fg)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMd)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMd)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private var agentMessageContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            messageRoleLabel
                .foregroundStyle(Theme.muted)

            if !message.steps.isEmpty {
                MessageStepsView(steps: message.steps)
            }

            MarkdownText(message.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var messageRoleLabel: some View {
        Text(message.role)
            .font(.system(size: isUser ? 11 : 13, weight: .semibold))
    }
}

// MARK: - Message Avatar
struct MessageAvatar: View {
    let role: String

    var body: some View {
        ZStack {
            Circle()
                .fill(role == "User" ? Theme.accentSoft : Theme.muted.opacity(0.10))
            Image(systemName: role == "User" ? "person.fill" : "command")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(role == "User" ? Theme.accent : Theme.muted)
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - Markdown Text

struct MarkdownText: View {
    let _text: String

    init(_ text: String) { self._text = text }

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: _text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Theme.fg)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(_text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Theme.fg)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Agent Process Steps

struct StepRow: View {
    let step: TurnStep

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: step.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(iconColor)
                    .frame(width: 15)

                Text(step.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(statusLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if let detail = step.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 21)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    private var iconColor: Color {
        switch step.status {
        case .completed: return .green
        case .active: return Theme.accent
        case .failed: return .red
        case .pending: return Theme.muted
        }
    }

    private var statusColor: Color {
        switch step.status {
        case .completed: return .green
        case .active: return Theme.accent
        case .failed: return .red
        case .pending: return Theme.muted
        }
    }

    private var statusLabel: String {
        switch step.status {
        case .completed: return "Done"
        case .active: return "In Progress"
        case .failed: return "Failed"
        case .pending: return "Waiting"
        }
    }
}

struct MessageStepsView: View {
    let steps: [TurnStep]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Agent Process")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)

                    Text("(\(progressText))")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted.opacity(0.7))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeOut(duration: 0.12), value: isExpanded)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(steps) { step in
                        StepRow(step: step)
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressText: String {
        let done = steps.filter { $0.status == .completed }.count
        return done < steps.count ? "\(done)/\(steps.count)" : "\(steps.count)"
    }
}

// MARK: - Command Approval Card
struct CommandApprovalCard: View {
    let approval: RelayApprovalPayload
    let approve: () -> Void
    let discard: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.warning.opacity(0.15))
                Image(systemName: "lock.open")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.warning)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("Approval required", systemImage: "lock.open")
                        .font(.system(size: 13, weight: .bold))
                    Spacer()
                    StatusPill(text: "Pending", tone: .warning)
                }
                Text(approval.reason ?? approval.method)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Text(approval.command ?? "-")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.fg)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
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
            .frame(maxWidth: 640, alignment: .leading)
            .background(Theme.warning.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .stroke(Theme.warning.opacity(0.28), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
            Spacer(minLength: 90)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

// MARK: - Composer
struct Composer: View {
    @ObservedObject var viewModel: MacShellViewModel
    @State private var editorHeight: CGFloat = 72
    @State private var hasStartedEditing = false
    private let minEditorHeight: CGFloat = 48
    private let maxEditorHeight: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            // Text editor
            PlainComposerTextEditor(
                text: $viewModel.draftText,
                onEditingActivity: { hasStartedEditing = true }
            )
                .padding(.horizontal, 12)
                .padding(.top, 11)
                .frame(height: editorHeight)
                .overlay(alignment: .topLeading) {
                    Text("提出后续修改要求")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.top, 11)
                        .allowsHitTesting(false)
                        .opacity(viewModel.draftText.isEmpty && !hasStartedEditing ? 1 : 0)
                }
                .onChange(of: viewModel.draftText) { _, newValue in
                    if !newValue.isEmpty { hasStartedEditing = true }
                    if newValue.hasSuffix("\n") {
                        viewModel.draftText = String(newValue.dropLast())
                        viewModel.sendDraft()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { hasStartedEditing = false }
                    }
                }

            // Resize handle (separate so it doesn't interfere with TextEditor)
            ResizeHandleView(
                editorHeight: $editorHeight,
                minHeight: minEditorHeight,
                maxHeight: maxEditorHeight
            )
            .frame(maxWidth: .infinity)
            .frame(height: 6)

            // Toolbar
            HStack(spacing: 6) {
                // Workspace picker — opens system folder picker
                Button(action: viewModel.selectWorkspace) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text(viewModel.workspaceFolderName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    // Hover effect handled by the chip container if needed
                }

                SessionMenu(
                    label: "Mode",
                    title: viewModel.planModeEnabled ? "Plan" : "Act",
                    items: ["Act", "Plan"],
                    selection: Binding(
                        get: { viewModel.planModeEnabled ? "Plan" : "Act" },
                        set: { viewModel.planModeEnabled = $0 == "Plan"; viewModel.recordSettingsUpdate() }
                    ),
                    onChange: {}
                )

                SessionMenu(label: "Model", title: viewModel.selectedModel, items: viewModel.modelOptions, selection: $viewModel.selectedModel, onChange: viewModel.recordSettingsUpdate)
                SessionMenu(label: "Effort", title: viewModel.selectedEffort.capitalized, items: viewModel.efforts, selection: $viewModel.selectedEffort, onChange: viewModel.recordSettingsUpdate)

                Spacer()

                SendButton(action: viewModel.sendDraft, disabled: viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 14)
        .background(Theme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMd)
                .stroke(Theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
        .padding(.horizontal, 36)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
    }
}

// MARK: - Composer Text Editor

#if os(macOS)
import AppKit

struct PlainComposerTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onEditingActivity: () -> Void

    func makeNSView(context: Context) -> NSView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = ComposerNSTextView()
        textView.delegate = context.coordinator
        textView.onEditingActivity = onEditingActivity
        textView.string = text
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = NSColor(Theme.fg)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = .zero

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let scrollView = nsView as? NSScrollView,
              let textView = scrollView.documentView as? ComposerNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.onEditingActivity = onEditingActivity
        textView.textColor = NSColor(Theme.fg)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onEditingActivity: onEditingActivity)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onEditingActivity: () -> Void
        weak var textView: NSTextView?

        init(text: Binding<String>, onEditingActivity: @escaping () -> Void) {
            self._text = text
            self.onEditingActivity = onEditingActivity
        }

        func textDidBeginEditing(_ notification: Notification) {
            onEditingActivity()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            onEditingActivity()
        }
    }
}

final class ComposerNSTextView: NSTextView {
    var onEditingActivity: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        onEditingActivity?()
        super.keyDown(with: event)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        onEditingActivity?()
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }
}
#endif

// MARK: - Send Button
struct SendButton: View {
    let action: () -> Void
    let disabled: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(disabled ? Theme.muted.opacity(0.3) : Theme.accentFg)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .background(disabled ? Color.clear : Theme.accent)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .disabled(disabled)
        .help("Send")
    }
}

// MARK: - Session Menu
struct SessionMenu: View {
    let label: String
    let title: String
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
            Text(displayTitle)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Theme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .help("\(label): \(displayTitle)")
    }

    private var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? label : title
    }
}

// MARK: - Resize Handle (AppKit)
struct ResizeHandleView: NSViewRepresentable {
    @Binding var editorHeight: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = HandleNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class Coordinator {
        var parent: ResizeHandleView
        init(_ parent: ResizeHandleView) { self.parent = parent }
    }
}

class HandleNSView: NSView {
    weak var coordinator: ResizeHandleView.Coordinator?
    private var trackingArea: NSTrackingArea?
    private var lastGlobalY: CGFloat = 0
    private var didPushCursor = false

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { pushResizeCursor() }
    override func mouseExited(with event: NSEvent) { popResizeCursor() }

    override func mouseDown(with event: NSEvent) {
        pushResizeCursor()
        lastGlobalY = event.locationInWindow.y
    }

    override func mouseDragged(with event: NSEvent) {
        guard let coord = coordinator else { return }
        let delta = event.locationInWindow.y - lastGlobalY
        // Up = taller, down = shorter
        coord.parent.editorHeight = max(
            coord.parent.minHeight,
            min(coord.parent.maxHeight, coord.parent.editorHeight - delta)
        )
        lastGlobalY = event.locationInWindow.y
    }

    override func mouseUp(with event: NSEvent) {}

    private func pushResizeCursor() {
        guard !didPushCursor else { return }
        NSCursor.resizeUpDown.push()
        didPushCursor = true
    }

    private func popResizeCursor() {
        guard didPushCursor else { return }
        NSCursor.pop()
        didPushCursor = false
    }
}
