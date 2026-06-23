import AgentClientCore
import SwiftUI

public struct PairingView: View {
    @ObservedObject var viewModel: RelayClientViewModel
    @State private var host = ""
    @State private var portText = ""
    @State private var payloadText = ""
    @State private var claimError: String?

    public init(viewModel: RelayClientViewModel) { self.viewModel = viewModel }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Connect to Mac Relay").font(.title2)

            // Quick paste from Mac Inspector
            VStack(alignment: .leading, spacing: 4) {
                Text("Paste pairing payload").font(.caption).foregroundStyle(.secondary)
                TextField("{\"host\": ...}", text: $payloadText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4)
                    .font(.system(size: 11, design: .monospaced))
                Button("Claim") {
                    claimError = nil
                    Task {
                        do { try await viewModel.claimFromPayload(payloadText) }
                        catch { claimError = error.localizedDescription }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(payloadText.isEmpty)
                if let claimError {
                    Text(claimError).font(.caption).foregroundStyle(.red)
                }
            }

            Divider()

            // Manual host:port
            TextField("Host", text: $host).textFieldStyle(.roundedBorder)
            TextField("Port", text: $portText).textFieldStyle(.roundedBorder)
            Button("Pair") {
                guard let port = UInt16(portText), !host.isEmpty else { return }
                Task { try? await viewModel.pair(host: host, port: port) }
            }
            .buttonStyle(.borderedProminent)

            if !viewModel.pairingCode.isEmpty {
                Text("Pairing: \(viewModel.pairingCode.prefix(16))...")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Clear Pairing", role: .destructive) {
                    viewModel.clearPairing()
                }
                .buttonStyle(.bordered)
            }
        }.padding()
    }
}

public struct ConnectionStatusView: View {
    @ObservedObject var viewModel: RelayClientViewModel
    public init(viewModel: RelayClientViewModel) { self.viewModel = viewModel }
    public var body: some View {
        VStack(spacing: 6) {
            HStack {
                Circle()
                    .fill(viewModel.heartbeatOnline ? .green : viewModel.currentState == .authFailed ? .red : .orange)
                    .frame(width: 8, height: 8)
                Text(viewModel.connectionStatus).font(.subheadline)
                Spacer()
                if viewModel.isConnecting { ProgressView().scaleEffect(0.7) }
                Button("Refresh") { Task { try? await viewModel.refresh() } }.buttonStyle(.bordered)
            }
            .padding(.horizontal)

            // State-aware actions
            HStack {
                if viewModel.currentState == .authFailed || viewModel.currentState == .offline {
                    Button("Reconnect") { Task { await viewModel.reconnect() } }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                if viewModel.currentState == .authFailed, viewModel.hasCredentials {
                    Button("Clear Credentials", role: .destructive) {
                        viewModel.clearPairing()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding(.horizontal)

            if let errorCode = viewModel.lastErrorCode {
                Text("Error: \(errorCode)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            HStack {
                if let lastHb = viewModel.lastHeartbeat {
                    Text("Last hb: \(lastHb, style: .relative) ago")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if viewModel.reconnectAttempt > 0 {
                    Text("Attempt: \(viewModel.reconnectAttempt)")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding(.horizontal)
        }
    }
}

public struct SessionSnapshotView: View {
    @ObservedObject var viewModel: RelayClientViewModel
    public init(viewModel: RelayClientViewModel) { self.viewModel = viewModel }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session").font(.headline)
            if let session = viewModel.sessionSnapshot {
                Text("Status: \(session.status)")
                Text("Model: \(session.model ?? "-")")
                if !session.assistantText.isEmpty {
                    Text("Assistant: \(session.assistantText.prefix(80))...").font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("No session data").foregroundStyle(.secondary) }
        }.padding()
    }
}

public struct EventReplayListView: View {
    @ObservedObject var viewModel: RelayClientViewModel
    public init(viewModel: RelayClientViewModel) { self.viewModel = viewModel }
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Events").font(.headline)
            if viewModel.replayEvents.isEmpty {
                Text("No events").foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.replayEvents.enumerated()), id: \.offset) { (i, event) in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("#\(event.seq)").font(.caption2).foregroundStyle(.secondary)
                            Text(event.type).font(.caption).bold()
                            Text(event.timestamp, style: .time).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }.padding()
    }
}
