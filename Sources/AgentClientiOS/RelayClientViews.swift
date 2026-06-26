import AgentClientCore
import SwiftUI

#if os(iOS)
import AVFoundation
import UIKit
#endif

public struct PairingView: View {
    @ObservedObject var viewModel: RelayClientViewModel
    @State private var host = ""
    @State private var portText = ""
    @State private var pairingInput = ""
    @State private var claimError: String?
    @State private var isClaimingPairing = false
    @State private var showingScanner = false

    public init(viewModel: RelayClientViewModel) { self.viewModel = viewModel }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pair with Mac")
                            .font(.largeTitle.bold())
                        Text(viewModel.connectionStatus)
                            .font(.subheadline)
                            .foregroundStyle(viewModel.heartbeatOnline ? .green : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Paste Pairing URI")
                            .font(.headline)
                        TextEditor(text: $pairingInput)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(minHeight: 116)
                            .padding(8)
                            .background(Color.secondary.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                            }
                            .autocorrectionDisabled()

                        HStack(spacing: 10) {
                            Button {
                                claimError = nil
                                pastePairingInput()
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.bordered)

                            #if os(iOS)
                            Button {
                                claimError = nil
                                showingScanner = true
                            } label: {
                                Label("Scan QR", systemImage: "qrcode.viewfinder")
                            }
                            .buttonStyle(.bordered)
                            #endif
                        }

                        Button {
                            claimCurrentInput()
                        } label: {
                            Label(viewModel.isConnecting || isClaimingPairing ? "Connecting..." : "Claim & Connect", systemImage: "link")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pairingInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isConnecting || isClaimingPairing)

                        if let claimError {
                            Text(claimError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Manual Host")
                            .font(.headline)
                        TextField("Mac LAN IP, e.g. 192.168.1.8", text: $host)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        TextField("Port", text: $portText)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            guard let port = UInt16(portText), !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            Task { try? await viewModel.pair(host: host.trimmingCharacters(in: .whitespacesAndNewlines), port: port) }
                        } label: {
                            Label("Connect by Host", systemImage: "network")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    if !viewModel.pairingCode.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Saved Pairing")
                                .font(.headline)
                            Text("\(viewModel.pairingCode.prefix(16))...")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Button("Clear Pairing", role: .destructive) { viewModel.clearPairing() }
                                .buttonStyle(.bordered)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding()
            }
            .background(Color.secondary.opacity(0.04))
            .navigationTitle("Pairing")
            #if os(iOS)
            .sheet(isPresented: $showingScanner) {
                QRScannerView { code in
                    pairingInput = code
                    showingScanner = false
                    claimCurrentInput()
                } onError: { message in
                    claimError = message
                    showingScanner = false
                }
            }
            #endif
        }
    }

    public func handleURL(_ url: URL) {
        claimPairing(url.absoluteString)
    }

    private func pastePairingInput() {
        #if os(iOS)
        pairingInput = UIPasteboard.general.string ?? pairingInput
        #endif
    }

    private func claimCurrentInput() {
        let input = pairingInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        claimPairing(input)
    }

    private func claimPairing(_ input: String) {
        guard !isClaimingPairing else { return }
        claimError = nil
        isClaimingPairing = true
        Task {
            do {
                try await viewModel.claimFromPayload(input)
                claimError = nil
                pairingInput = ""
            } catch {
                if viewModel.currentState == .connected {
                    claimError = nil
                } else {
                    claimError = error.localizedDescription
                }
            }
            isClaimingPairing = false
        }
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
                        Text(event.summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .padding(.vertical, 2)
                }
            }
        }.padding()
    }
}

#if os(iOS)
private struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.delegate = context.coordinator
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onCode: (String) -> Void
        private var didScan = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didScan,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr,
                  let value = object.stringValue else { return }
            didScan = true
            onCode(value)
        }
    }
}

private final class QRScannerViewController: UIViewController {
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configureCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupScanner()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.setupScanner() : self?.onError?("Camera access denied.")
                }
            }
        default:
            onError?("Camera access denied. Enable camera permission in Settings.")
        }
    }

    private func setupScanner() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            onError?("Camera is unavailable.")
            return
        }

        let output = AVCaptureMetadataOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            onError?("QR scanner cannot start.")
            return
        }

        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(delegate, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }
}
#endif
