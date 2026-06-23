import AgentClientCore
import SwiftUI

public struct PairingView: View {
    @ObservedObject var viewModel: RelayClientViewModel
    @State private var host = ""
    @State private var portText = ""

    public init(viewModel: RelayClientViewModel) { self.viewModel = viewModel }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Connect to Mac Relay").font(.title2)
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
            }
        }.padding()
    }
}

public struct ConnectionStatusView: View {
    @ObservedObject var viewModel: RelayClientViewModel
    public init(viewModel: RelayClientViewModel) { self.viewModel = viewModel }

    public var body: some View {
        HStack {
            Circle().fill(viewModel.heartbeatOnline ? .green : .red).frame(width: 8, height: 8)
            Text(viewModel.connectionStatus).font(.subheadline)
            Spacer()
            if viewModel.isConnecting { ProgressView().scaleEffect(0.7) }
            Button("Refresh") { Task { try? await viewModel.refresh() } }.buttonStyle(.bordered)
        }.padding(.horizontal)
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
            } else {
                Text("No session data").foregroundStyle(.secondary)
            }
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
                ForEach(viewModel.replayEvents.indices, id: \.self) { i in
                    let event = viewModel.replayEvents[i]
                    HStack {
                        Text("#\(event.seq)").font(.caption2).foregroundStyle(.secondary)
                        Text(event.type).font(.caption)
                    }
                }
            }
        }.padding()
    }
}
