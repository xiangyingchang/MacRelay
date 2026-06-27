import SwiftUI
import AgentClientCore

/// Full-session workspace with scrollable conversation stream and bottom composer.
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
                        proxy.scrollTo(viewModel.conversationMessages.count - 1, anchor: .bottom)
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
                    Task {
                        try? await viewModel.sendTurn(text: text)
                    }
                }
            )
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
        // Strip prefix like "[user] " or "[assistant] "
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
