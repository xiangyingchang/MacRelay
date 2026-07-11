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
    @State private var isQRDetected = false

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
                } onQRPosition: { detected in
                    isQRDetected = detected
                } onError: { message in
                    claimError = message
                }

                cornerViewfinder

                // Scanning line animation (idle state only)
                if !isClaimingPairing && !isQRDetected {
                    scanningLine
                }
            }
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        isQRDetected ? Color.green.opacity(0.6) : Color.primary.opacity(0.1),
                        lineWidth: isQRDetected ? 2 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isQRDetected)

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

    /// Animated scanning line that sweeps vertically through the viewfinder.
    private var scanningLine: some View {
        GeometryReader { geo in
            ScanningLineView(height: geo.size.height)
        }
    }
    #endif
}

// MARK: - Settings View (replaces bare ConnectionStatusView)

public struct SettingsView: View {
    @ObservedObject var viewModel: RelayClientViewModel

    public init(viewModel: RelayClientViewModel) { self.viewModel = viewModel }

    private let providers = ["Codex CLI", "Claude Code"]

    public var body: some View {
        NavigationStack {
            Form {
                // MARK: Provider
                Section {
                    Picker("Provider", selection: $viewModel.selectedProvider) {
                        ForEach(providers, id: \.self) { p in
                            Text(p).tag(p)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: viewModel.selectedProvider) { _, _ in
                        sendProviderUpdate()
                    }
                    Text("Change the AI agent runtime on your Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Agent", systemImage: "square.stack.3d.up")
                }

                // MARK: Session defaults
                Section {
                    HStack {
                        Text("Model")
                        Spacer()
                        Text(viewModel.selectedModel.isEmpty ? "—" : viewModel.selectedModel)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Effort")
                        Spacer()
                        Text(viewModel.selectedEffort.capitalized)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Mode")
                        Spacer()
                        Text(viewModel.planModeEnabled ? "Plan" : "Act")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Access")
                        Spacer()
                        Text(viewModel.permissionMode)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Session Defaults", systemImage: "gearshape")
                } footer: {
                    Text("These are set in the Session toolbar. Changing them here takes effect on next send.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: Connection
                Section {
                    HStack {
                        Label("Status", systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.heartbeatOnline ? Color.green : viewModel.currentState == .authFailed ? .red : .orange)
                                .frame(width: 8, height: 8)
                            Text(viewModel.connectionStatus)
                                .font(.subheadline)
                        }
                    }
                    if let lastHb = viewModel.lastHeartbeat {
                        HStack {
                            Text("Last heartbeat")
                            Spacer()
                            Text(lastHb, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("Connection", systemImage: "link")
                }

                // MARK: Error info
                if let errorCode = viewModel.lastErrorCode {
                    Section {
                        Text(errorCode)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red)
                    } header: {
                        Label("Last Error", systemImage: "exclamationmark.triangle")
                    }
                }

                // MARK: Actions
                Section {
                    if viewModel.currentState == .authFailed || viewModel.currentState == .offline {
                        Button(action: { Task { await viewModel.reconnect() } }) {
                            Label("Reconnect", systemImage: "arrow.clockwise")
                        }
                    }
                    Button(role: .destructive, action: viewModel.clearPairing) {
                        Label("Disconnect & Clear Pairing", systemImage: "link.badge.minus")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func sendProviderUpdate() {
        Task {
            await viewModel.sendSettingsUpdate()
        }
    }
}

// MARK: - Scanner Camera

#if os(iOS)
private struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onQRPosition: (Bool) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onQRPosition: onQRPosition)
    }

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.delegate = context.coordinator
        controller.onError = onError
        context.coordinator.viewController = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onCode: (String) -> Void
        private let onQRPosition: (Bool) -> Void
        private var didScan = false
        weak var viewController: QRScannerViewController?

        init(onCode: @escaping (String) -> Void, onQRPosition: @escaping (Bool) -> Void) {
            self.onCode = onCode
            self.onQRPosition = onQRPosition
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !didScan else { return }

            let qrObjects = metadataObjects.compactMap { $0 as? AVMetadataMachineReadableCodeObject }
                .filter { $0.type == .qr }

            if let first = qrObjects.first {
                onQRPosition(true)
                // Actively focus and zoom on the detected QR code
                viewController?.handleQRDetected(first)

                if let value = first.stringValue {
                    didScan = true
                    onCode(value)
                }
            } else {
                onQRPosition(false)
                viewController?.handleQRLost()
            }
        }
    }
}

private final class QRScannerViewController: UIViewController {
    weak var delegate: AVCaptureMetadataOutputObjectsDelegate?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var device: AVCaptureDevice?
    private var focusView: UIView?
    private var highlightView: UIView?

    private var lastFocusTime: Date = .distantPast
    private var lastZoomTime: Date = .distantPast
    private let focusCooldown: TimeInterval = 0.15
    private let zoomCooldown: TimeInterval = 0.3
    private var isZoomed = false
    private let defaultZoomFactor: CGFloat = 1.0
    private let maxZoomFactor: CGFloat = 5.0

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

    // MARK: - Camera Setup

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
        guard let cam = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: cam) else {
            onError?("Camera is unavailable.")
            return
        }

        let output = AVCaptureMetadataOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            onError?("QR scanner cannot start.")
            return
        }

        // High quality preset for better resolution during digital zoom
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(delegate, queue: .main)
        output.metadataObjectTypes = [.qr]

        // NOTE: No rectOfInterest — scan the ENTIRE frame.
        // We want to detect QR codes anywhere and actively focus/zoom on them.

        self.device = cam
        configureCameraDevice(cam)

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        // Tap-to-focus gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)

        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    private func configureCameraDevice(_ cam: AVCaptureDevice) {
        do {
            try cam.lockForConfiguration()

            if cam.isFocusModeSupported(.continuousAutoFocus) {
                cam.focusMode = .continuousAutoFocus
            }
            if cam.isExposureModeSupported(.continuousAutoExposure) {
                cam.exposureMode = .continuousAutoExposure
            }
            if cam.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                cam.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            cam.unlockForConfiguration()
        } catch {}
    }

    // MARK: - Auto-Focus + Zoom on QR Detection

    /// Called by the Coordinator when a QR code is detected in the frame.
    /// Actively focuses on the QR code and applies digital zoom.
    func handleQRDetected(_ metadataObject: AVMetadataMachineReadableCodeObject) {
        guard let cam = device, let preview = previewLayer else { return }

        // Convert metadata bounds (normalized 0-1, origin bottom-left) to layer coordinates
        let layerRect = preview.layerRectConverted(fromMetadataOutputRect: metadataObject.bounds)
        let center = CGPoint(x: layerRect.midX, y: layerRect.midY)

        // Normalize to 0-1 for focusPointOfInterest
        let normalizedCenter = CGPoint(
            x: center.x / view.bounds.width,
            y: center.y / view.bounds.height
        )

        let now = Date()

        // Focus on QR code position (with cooldown)
        if now.timeIntervalSince(lastFocusTime) > focusCooldown {
            lastFocusTime = now
            do {
                try cam.lockForConfiguration()

                if cam.isFocusPointOfInterestSupported {
                    cam.focusPointOfInterest = normalizedCenter
                }
                if cam.isFocusModeSupported(.autoFocus) {
                    cam.focusMode = .autoFocus
                }
                if cam.isExposurePointOfInterestSupported {
                    cam.exposurePointOfInterest = normalizedCenter
                }
                if cam.isExposureModeSupported(.autoExpose) {
                    cam.exposureMode = .autoExpose
                }

                cam.unlockForConfiguration()
            } catch {}
        }

        // Digital zoom: smaller QR code in frame → more zoom (with cooldown)
        if now.timeIntervalSince(lastZoomTime) > zoomCooldown {
            lastZoomTime = now
            let qrFraction = max(layerRect.width / view.bounds.width, 0.01)
            let targetZoom = min(1.2 / qrFraction, maxZoomFactor)

            // Only zoom in, don't zoom back out abruptly
            if targetZoom > cam.videoZoomFactor * 1.05 {
                isZoomed = true
                do {
                    try cam.lockForConfiguration()
                    cam.ramp(toVideoZoomFactor: targetZoom, withRate: 3.0)
                    cam.unlockForConfiguration()
                } catch {}
            }
        }

        // Show green highlight at QR code position
        showHighlight(at: layerRect)
    }

    /// Called when QR code is no longer detected — gradually reset zoom.
    func handleQRLost() {
        guard let cam = device else { return }

        if isZoomed {
            isZoomed = false
            do {
                try cam.lockForConfiguration()
                cam.ramp(toVideoZoomFactor: defaultZoomFactor, withRate: 2.0)
                cam.unlockForConfiguration()
            } catch {}
        }

        // Return to continuous autofocus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let cam = self.device else { return }
            do {
                try cam.lockForConfiguration()
                if cam.isFocusModeSupported(.continuousAutoFocus) {
                    cam.focusMode = .continuousAutoFocus
                }
                if cam.isExposureModeSupported(.continuousAutoExposure) {
                    cam.exposureMode = .continuousAutoExposure
                }
                cam.unlockForConfiguration()
            } catch {}
        }

        hideHighlight()
    }

    // MARK: - Visual Feedback

    private func showHighlight(at rect: CGRect) {
        if highlightView == nil {
            let v = UIView()
            v.layer.borderColor = UIColor.systemGreen.cgColor
            v.layer.borderWidth = 2
            v.layer.cornerRadius = 4
            v.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.08)
            view.addSubview(v)
            highlightView = v
        }
        // Add some padding around the detected QR code
        let padding: CGFloat = 8
        highlightView?.frame = rect.insetBy(dx: -padding, dy: -padding)
        highlightView?.alpha = 1
    }

    private func hideHighlight() {
        UIView.animate(withDuration: 0.3) {
            self.highlightView?.alpha = 0
        }
    }

    // MARK: - Tap to Focus

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let cam = device else { return }
        let point = gesture.location(in: view)
        let focusPoint = CGPoint(
            x: point.x / view.bounds.width,
            y: point.y / view.bounds.height
        )

        do {
            try cam.lockForConfiguration()

            if cam.isFocusPointOfInterestSupported {
                cam.focusPointOfInterest = focusPoint
            }
            if cam.isFocusModeSupported(.autoFocus) {
                cam.focusMode = .autoFocus
            }
            if cam.isExposurePointOfInterestSupported {
                cam.exposurePointOfInterest = focusPoint
            }
            if cam.isExposureModeSupported(.autoExpose) {
                cam.exposureMode = .autoExpose
            }

            cam.unlockForConfiguration()
        } catch {}

        showFocusIndicator(at: point)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, let cam = self.device else { return }
            do {
                try cam.lockForConfiguration()
                if cam.isFocusModeSupported(.continuousAutoFocus) {
                    cam.focusMode = .continuousAutoFocus
                }
                if cam.isExposureModeSupported(.continuousAutoExposure) {
                    cam.exposureMode = .continuousAutoExposure
                }
                cam.unlockForConfiguration()
            } catch {}
        }
    }

    private func showFocusIndicator(at point: CGPoint) {
        focusView?.removeFromSuperview()

        let size: CGFloat = 70
        let indicator = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        indicator.center = point
        indicator.layer.borderColor = UIColor.white.cgColor
        indicator.layer.borderWidth = 1.5
        indicator.layer.cornerRadius = 4
        indicator.backgroundColor = .clear
        indicator.alpha = 0
        view.addSubview(indicator)
        focusView = indicator

        UIView.animate(withDuration: 0.15) {
            indicator.alpha = 1
            indicator.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        } completion: { _ in
            UIView.animate(withDuration: 0.1) {
                indicator.transform = .identity
            }
        }

        UIView.animate(withDuration: 0.3, delay: 0.8) {
            indicator.alpha = 0
        }
    }
}

// MARK: - Scanning Line Animation

/// A UIView that renders an animated horizontal line sweeping vertically.
private final class ScanningLineUIView: UIView {
    private let lineLayer = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false

        lineLayer.backgroundColor = UIColor.white.withAlphaComponent(0.6).cgColor
        lineLayer.cornerRadius = 1
        layer.addSublayer(lineLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        lineLayer.frame = CGRect(x: 16, y: 0, width: bounds.width - 32, height: 2)
    }

    func startAnimating() {
        let animation = CABasicAnimation(keyPath: "position.y")
        animation.fromValue = 8.0
        animation.toValue = bounds.height - 8.0
        animation.duration = 2.0
        animation.repeatCount = .infinity
        animation.autoreverses = true
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        lineLayer.add(animation, forKey: "sweep")
    }

    func stopAnimating() {
        lineLayer.removeAnimation(forKey: "sweep")
    }
}

private struct ScanningLineView: UIViewRepresentable {
    let height: CGFloat

    func makeUIView(context: Context) -> ScanningLineUIView {
        let view = ScanningLineUIView(frame: CGRect(x: 0, y: 0, width: 280, height: height))
        view.startAnimating()
        return view
    }

    func updateUIView(_ uiView: ScanningLineUIView, context: Context) {}
}
#endif
