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

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MessageAvatar(role: message.role)

            VStack(alignment: .leading, spacing: 6) {
                Text(message.role)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(message.role == "User" ? Theme.accent : Theme.muted)
                Text(message.text)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.fg)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))

            Spacer(minLength: 90)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

// MARK: - Message Avatar
struct MessageAvatar: View {
    let role: String

    var body: some View {
        ZStack {
            Circle()
                .fill(role == "User" ? Theme.accentSoft : Theme.surface)
            Image(systemName: role == "User" ? "person.fill" : "command")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(role == "User" ? Theme.accent : Theme.muted)
        }
        .frame(width: 28, height: 28)
        .overlay(
            role == "User" ? nil :
                Circle().stroke(Theme.border, lineWidth: 1)
        )
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
    private let minEditorHeight: CGFloat = 48
    private let maxEditorHeight: CGFloat = 320

    var body: some View {
        VStack(spacing: 0) {
            // Text editor
            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.draftText)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.fg)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(.horizontal, 12)
                    .padding(.top, 9)
                    .frame(height: editorHeight)

                if viewModel.draftText.isEmpty {
                    Text("提出后续修改要求")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted.opacity(0.7))
                        .padding(.horizontal, 16)
                        .padding(.top, 11)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: editorHeight)

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
                // Workspace picker — transparent, no border (HTML style)
                Button(action: { /* pick workspace */ }) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text(viewModel.projectCWD)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 80, alignment: .leading)
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

// MARK: - Plan Toggle
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
