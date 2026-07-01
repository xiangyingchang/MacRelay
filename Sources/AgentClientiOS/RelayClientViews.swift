import AgentClientCore
import SwiftUI

#if os(iOS)
import AVFoundation
import UIKit
#endif

public struct PairingView: View {
    @ObservedObject var viewModel: RelayClientViewModel
    @State private var pairingInput = ""
    @State private var claimError: String?
    @State private var isClaimingPairing = false
    @State private var showingPasteSheet = false

    public init(viewModel: RelayClientViewModel) { self.viewModel = viewModel }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.heartbeatOnline {
                    connectedContent
                } else {
                    #if os(iOS)
                    scanContent
                    #else
                    pasteContent
                    #endif
                }
            }
            .navigationTitle("Connect to Mac")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    public func handleURL(_ url: URL) {
        let text = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        claimFromInput(text)
    }

    // MARK: - Scan State (iOS)

    #if os(iOS)
    private var scanContent: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero: QR Scanner viewfinder
            ZStack {
                QRScannerView { code in
                    guard !isClaimingPairing else { return }
                    pairingInput = code
                    claimFromInput(code)
                } onError: { message in
                    claimError = message
                }

                cornerViewfinder
            }
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )

            Spacer().frame(height: 24)

            Text("Point your camera at the QR code\nshown on your Mac")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 16)

            // Status indicator
            HStack(spacing: 6) {
                if isClaimingPairing {
                    ProgressView()
                        .controlSize(.small)
                }
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(viewModel.connectionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = claimError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 8)
                    .padding(.horizontal, 32)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Subtle fallback
            Button {
                showingPasteSheet = true
            } label: {
                HStack(spacing: 4) {
                    Text("Paste pairing URI")
                        .font(.caption)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showingPasteSheet) {
            pasteSheet
        }
    }
    #endif

    // MARK: - Paste Content (non-iOS fallback)

    private var pasteContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Paste Pairing URI")
                .font(.headline)

            TextEditor(text: $pairingInput)
                .font(.system(size: 13, design: .monospaced))
                .frame(minHeight: 100, maxHeight: 200)
                .padding(8)
                .background(Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .autocorrectionDisabled()

            Button {
                claimFromInput(pairingInput)
            } label: {
                Text("Connect")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(pairingInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isClaimingPairing)

            if let error = claimError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(viewModel.connectionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Connected State

    private var connectedContent: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Spacer().frame(height: 16)

            Text("Connected")
                .font(.title2.bold())

            if !viewModel.pairingCode.isEmpty {
                Text("Paired with Mac")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }

            Spacer()

            Button(role: .destructive) {
                viewModel.clearPairing()
            } label: {
                Label("Disconnect", systemImage: "link.badge.minus")
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Paste Fallback Sheet

    private var pasteSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: $pairingInput)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .autocorrectionDisabled()

                Button {
                    claimFromInput(pairingInput)
                } label: {
                    Text("Connect")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pairingInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isClaimingPairing)
            }
            .padding()
            .navigationTitle("Paste Pairing URI")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingPasteSheet = false }
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        pairingInput = UIPasteboard.general.string ?? pairingInput
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                }
                #endif
            }
        }
    }

    // MARK: - Helpers

    private func claimFromInput(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isClaimingPairing else { return }
        claimError = nil
        isClaimingPairing = true
        Task {
            do {
                try await viewModel.claimFromPayload(text)
                claimError = nil
                pairingInput = ""
                showingPasteSheet = false
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

    private var statusColor: Color {
        if viewModel.heartbeatOnline { return .green }
        if viewModel.currentState == .authFailed { return .red }
        if isClaimingPairing { return .orange }
        return .secondary
    }

    /// Viewfinder corner brackets overlaid on the camera preview.
    #if os(iOS)
    private var cornerViewfinder: some View {
        GeometryReader { geo in
            let l: CGFloat = 28   // corner arm length
            let w: CGFloat = 3    // stroke width
            let p: CGFloat = 16   // inset from edge

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: p, y: p + l))
                    path.addLine(to: CGPoint(x: p, y: p))
                    path.addLine(to: CGPoint(x: p + l, y: p))
                }
                .stroke(.white, lineWidth: w)

                Path { path in
                    path.move(to: CGPoint(x: geo.size.width - p - l, y: p))
                    path.addLine(to: CGPoint(x: geo.size.width - p, y: p))
                    path.addLine(to: CGPoint(x: geo.size.width - p, y: p + l))
                }
                .stroke(.white, lineWidth: w)

                Path { path in
                    path.move(to: CGPoint(x: p, y: geo.size.height - p - l))
                    path.addLine(to: CGPoint(x: p, y: geo.size.height - p))
                    path.addLine(to: CGPoint(x: p + l, y: geo.size.height - p))
                }
                .stroke(.white, lineWidth: w)

                Path { path in
                    path.move(to: CGPoint(x: geo.size.width - p - l, y: geo.size.height - p))
                    path.addLine(to: CGPoint(x: geo.size.width - p, y: geo.size.height - p))
                    path.addLine(to: CGPoint(x: geo.size.width - p, y: geo.size.height - p - l))
                }
                .stroke(.white, lineWidth: w)
            }
        }
    }
    #endif
}

// MARK: - Connection Status (used by app directly)

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

// MARK: - Scanner Camera

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
