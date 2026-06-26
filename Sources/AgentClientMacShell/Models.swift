import AgentClientCore
import Combine
import Foundation
import SwiftUI

// MARK: - Runtime Mode

enum RuntimeMode: String, CaseIterable {
    case mock = "Mock"
    case real = "Real"
}

// MARK: - MacShellViewModel

@MainActor
final class MacShellViewModel: ObservableObject {
    let runtime = CodexRuntimeBridge()
    let relayService = MacRelayService(
        connection: ConnectionSnapshotPayload(
            deviceID: "local-mac-ui",
            macName: ProcessInfo.processInfo.hostName,
            isPaired: true,
            isOnline: true
        )
    )

    @Published private(set) var snapshot = MockSnapshotFactory.makeRelaySnapshot()
    @Published private(set) var relaySnapshot = RelaySnapshotPayload(
        activeSessionID: nil,
        session: nil,
        connection: ConnectionSnapshotPayload(isPaired: true, isOnline: true),
        pendingApprovals: [],
        lastEventSeq: 0
    )
    @Published private(set) var relayEventCount = 0
    @Published private(set) var relayStatusText = "Relay idle"
    @Published private(set) var relayServerRunning = false
    @Published private(set) var relayServerPort: UInt16 = 0
    @Published private(set) var relayServerLastError: String?
    @Published private(set) var relayServerConfiguredToStart: Bool
    @Published private(set) var relayLANIPv4: String?
    @Published private(set) var relayServerHost: String
    @Published private(set) var relayHostMode: String  // "local" or "lan"

    private let relayServerConfigKey = "MacRelayHTTPServerEnabled"
    private let relayHostModeConfigKey = "MacRelayHostMode"
    private lazy var relayHTTPServer = MacRelayHTTPServer(relayService: relayService)
    private lazy var relayWSServer = MacRelayWebSocketServer(relayService: relayService)
    @Published var runtimeMode: RuntimeMode = .mock
    @Published var activeRunID = "run-polish"
    @Published var activeNav = "Codex"
    @Published var selectedModel: String
    @Published var selectedEffort = "low"
    @Published var selectedPermissionMode = "Read Only"
    @Published var planModeEnabled = true
    @Published var draftText = ""
    @Published var selectedFileID = "mac-shell"
    @Published var commandApprovalVisible = true
    @Published private(set) var commandLog: [RelayCommandLogEntry] = [
        RelayCommandLogEntry(type: .sessionStart, detail: "session.start cwd=/private/tmp/MacRelay"),
        RelayCommandLogEntry(type: .snapshotGet, detail: "snapshot.get seq=8")
    ]

    /// ID of the streaming assistant message currently being built.
    /// Used to update it in-place as deltas arrive.
    private var streamingMessageID: UUID?
    /// Turn id that owns the current streaming placeholder.
    private var streamingTurnID: String?
    /// Previous assistant text length, to detect new delta content.
    private var lastAssistantTextLength = 0
    /// Whether we've started a real session (to clear mock messages once).
    private var hasStartedRealSession = false

    let navItems: [NavItem] = [
        NavItem(title: "Codex", symbol: "message"),
        NavItem(title: "Sessions", symbol: "clock"),
        NavItem(title: "Files", symbol: "folder"),
        NavItem(title: "Approvals", symbol: "checklist"),
        NavItem(title: "Models", symbol: "square.stack.3d.up"),
        NavItem(title: "Settings", symbol: "gearshape")
    ]

    let runs: [ActiveRun] = [
        ActiveRun(id: "run-polish", title: "Mac shell polish", profile: "Codex", status: "running"),
        ActiveRun(id: "run-relay", title: "Relay M1", profile: "Codex", status: "completed")
    ]

    let sessions: [SessionListItem] = [
        SessionListItem(id: "run-polish", title: "Mac shell polish", subtitle: "Hermes-style workspace, approval, diff", status: "running", count: 2),
        SessionListItem(id: "iphone", title: "iPhone handoff", subtitle: "LAN pairing and session takeover", status: "waiting", count: 1),
        SessionListItem(id: "relay", title: "App-server relay", subtitle: "stdio, snapshots, replay, approval", status: "completed", count: 0),
        SessionListItem(id: "prd", title: "Product spec", subtitle: "PRD and execution plan in Obsidian", status: "completed", count: 0)
    ]

    @Published var messages: [ConversationMessage] = [
        ConversationMessage(role: "User", text: "参考 Hermes Desktop，把 Mac 客户端的 UI 调整成更高级的工作台，而不是普通三栏 demo。"),
        ConversationMessage(role: "Codex", text: "已读取 Hermes Desktop 的 Layout、SidebarRecentSessions、ActiveSessionsBar、ChatInput、ModelPicker 和 ReasoningEffortPicker。v3 会采用左侧导航 + 近期 session、顶部 active session bar、底部复合 composer。"),
        ConversationMessage(role: "Tool", text: "swift build --product AgentClientMacShell")
    ]

    @Published var files: [ChangedFileMock] = [
        ChangedFileMock(id: "mac-shell", path: "Sources/AgentClientMacShell/main.swift", status: "Modified", impact: "+420 -360", reviewState: "Pending"),
        ChangedFileMock(id: "ui-doc", path: "产品/AI 编程 CLI 客户端 UI 设计基准.md", status: "Updated", impact: "+54 -0", reviewState: "Approved"),
        ChangedFileMock(id: "plan", path: "产品/AI 编程 CLI 客户端落地执行计划.md", status: "Updated", impact: "+31 -0", reviewState: "Pending")
    ]

    let fallbackModels = ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini"]
    let efforts = ["low", "medium", "high", "xhigh"]
    let permissions = ["Read Only", "Default", "Full Access"]
    private var cancellables = Set<AnyCancellable>()

    var activeSession: SessionListItem {
        sessions.first { $0.id == activeRunID } ?? sessions[0]
    }

    var selectedFile: ChangedFileMock {
        files.first { $0.id == selectedFileID } ?? files[0]
    }

    var displayFiles: [ChangedFileMock] {
        guard runtimeMode == .real else { return files }
        return runtime.snapshot.fileChanges.values
            .sorted { ($0.path ?? $0.id) < ($1.path ?? $1.id) }
            .map { change in
                ChangedFileMock(
                    id: change.id,
                    path: change.path ?? change.id,
                    status: (change.changeKind ?? "Changed").capitalized,
                    impact: change.diffLength > 0 ? "diff \(change.diffLength)" : "Changed",
                    reviewState: "Pending"
                )
            }
    }

    var selectedDisplayFile: ChangedFileMock? {
        let files = displayFiles
        return files.first { $0.id == selectedFileID } ?? files.first
    }

    var pendingApproval: RelayApprovalPayload? {
        if runtimeMode == .real, let realApproval = runtime.snapshot.pendingApprovals.values.first(where: { $0.isPending }) {
            return RelayApprovalPayload(approval: realApproval)
        }
        guard runtimeMode == .mock, commandApprovalVisible else { return nil }
        return snapshot.pendingApprovals.first
    }

    var modelOptions: [String] {
        runtime.modelNames.isEmpty ? fallbackModels : runtime.modelNames
    }

    var runtimeStatusTone: StatusPill.Tone {
        runtime.detection.isInstalled ? .success : .warning
    }

    /// Real-mode session status text derived from runtime.snapshot.
    /// Maps SessionStatus + streaming/error state to a user-facing label.
    var realSessionStatusText: String {
        guard runtimeMode == .real else { return activeSession.status.capitalized }
        switch runtime.snapshot.status {
        case .idle:
            return "Idle"
        case .active:
            // Refine "active" into running vs streaming
            if runtime.snapshot.pendingApprovals.values.contains(where: { $0.isPending }) {
                return "Waiting"
            }
            if let turn = runtime.snapshot.activeTurn, !turn.isCompleted {
                return turn.assistantText.isEmpty ? "Running" : "Streaming"
            }
            return "Running"
        case .waitingOnApproval:
            return "Waiting"
        case .systemError:
            return "Error"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        case .exited:
            return "Exited"
        }
    }

    /// Real-mode session status pill color derived from runtime.snapshot.
    var realSessionStatusTone: StatusPill.Tone {
        guard runtimeMode == .real else {
            return activeSession.status == "waiting" ? .warning : .accent
        }
        switch runtime.snapshot.status {
        case .idle: return .accent
        case .active:
            return runtime.snapshot.pendingApprovals.values.contains(where: { $0.isPending })
                ? .warning : .accent
        case .waitingOnApproval: return .warning
        case .systemError: return .warning
        case .completed: return .success
        case .failed: return .warning
        case .exited: return .warning
        }
    }

    /// CWD for the current project.
    var projectCWD: String {
        "/private/tmp/MacRelay"
    }

    /// Sandbox for thread/start. Codex app-server 0.141.0 expects kebab-case.
    var threadSandboxValue: String {
        switch selectedPermissionMode {
        case "Full Access": return "danger-full-access"
        case "Default": return "workspace-write"
        default: return "read-only"
        }
    }

    /// Sandbox for turn/start sandboxPolicy.type. Codex app-server 0.141.0 expects camelCase here.
    var turnSandboxValue: String {
        switch selectedPermissionMode {
        case "Full Access": return "dangerFullAccess"
        case "Default": return "workspaceWrite"
        default: return "readOnly"
        }
    }

    /// Map permission mode picker value to app-server approval policy.
    var approvalPolicyValue: String {
        switch selectedPermissionMode {
        case "Full Access": return "never"
        case "Default": return "on-request"
        default: return "on-request"
        }
    }

    init() {
        let initial = MockSnapshotFactory.makeRelaySnapshot()
        self.snapshot = initial
        self.selectedModel = initial.session?.model ?? "gpt-5.5"
        self.relayServerConfiguredToStart = UserDefaults.standard.bool(forKey: relayServerConfigKey)
        let lanIP = RelayHostDetector.primaryLANIPv4()
        self.relayLANIPv4 = lanIP
        let savedMode = UserDefaults.standard.string(forKey: relayHostModeConfigKey) ?? (lanIP == nil ? "local" : "lan")
        var hostMode = savedMode
        if hostMode == "lan", lanIP == nil {
            hostMode = "local"
        }
        self.relayHostMode = hostMode
        self.relayServerHost = hostMode == "lan" ? (lanIP ?? "127.0.0.1") : "127.0.0.1"
        self.relaySnapshot = relayService.snapshotEnvelope().payload

        if relayServerConfiguredToStart {
            startRelayServer(persistConfiguration: false)
        }

        // Forward runtime objectWillChange so SwiftUI redraws when bridge changes
        runtime.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)

        // Subscribe to runtime snapshot for real-mode streaming
        runtime.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] newSnapshot in
                self?.handleSnapshotUpdate(newSnapshot)
            }
            .store(in: &cancellables)

        runtime.$latestTurnID
            .receive(on: RunLoop.main)
            .sink { [weak self] turnID in
                self?.handleLatestTurnID(turnID)
            }
            .store(in: &cancellables)

        runtime.onEventReceived = { [weak self] event in
            Task { @MainActor in
                self?.ingestRelayEvent(event)
            }
        }
    }

    // MARK: - Actions

    func sendDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch runtimeMode {
        case .mock:
            sendDraftMock(trimmed)
        case .real:
            sendDraftReal(trimmed)
        }

        draftText = ""
    }

    func approveCommand() {
        if runtimeMode == .real, let (_, approval) = runtime.snapshot.pendingApprovals.first(where: { $0.value.isPending }) {
            do {
                try runtime.resolveApproval(requestID: approval.requestID, decision: "accept")
                messages.append(ConversationMessage(role: "System", text: "Command approval accepted (request \(approval.requestID))."))
                record(.approvalResolve, "approval.resolve request=\(approval.requestID) decision=accept")
            } catch {
                messages.append(ConversationMessage(role: "Tool", text: "Failed to resolve approval: \(error)"))
            }
            return
        }
        commandApprovalVisible = false
        messages.append(ConversationMessage(role: "System", text: "Command approval accepted."))
        record(.approvalResolve, "approval.resolve request=0 decision=accept")
    }

    func discardCommand() {
        if runtimeMode == .real, let (_, approval) = runtime.snapshot.pendingApprovals.first(where: { $0.value.isPending }) {
            do {
                try runtime.resolveApproval(requestID: approval.requestID, decision: "reject")
                messages.append(ConversationMessage(role: "System", text: "Command approval rejected (request \(approval.requestID))."))
                record(.approvalResolve, "approval.resolve request=\(approval.requestID) decision=reject")
            } catch {
                messages.append(ConversationMessage(role: "Tool", text: "Failed to resolve approval: \(error)"))
            }
            return
        }
        commandApprovalVisible = false
        messages.append(ConversationMessage(role: "System", text: "Command approval discarded."))
        record(.approvalResolve, "approval.resolve request=0 decision=reject")
    }

    func approveFile(_ fileID: String) {
        setFile(fileID, state: "Approved")
        record(.fileApprove, "file.approve id=\(fileID)")
    }

    func discardFile(_ fileID: String) {
        setFile(fileID, state: "Discarded")
        record(.fileDiscardSessionChanges, "file.discardSessionChanges id=\(fileID)")
    }

    func recordSettingsUpdate() {
        // Real mode: send thread/settings/update when app-server is initialized
        // and a thread exists. Otherwise silently skip — the settings will be
        // applied at thread/start or turn/start time via enqueueDraft.
        if runtimeMode == .real, runtime.isInitialized, runtime.currentThreadID != nil {
            do {
                try runtime.updateSettings(
                    model: selectedModel,
                    effort: selectedEffort,
                    approvalPolicy: approvalPolicyValue,
                    sandboxPolicy: turnSandboxValue
                )
            } catch {
                // Don't surface to user — settings updates are best-effort
                // and the next turn/start will apply them anyway.
            }
        }

        record(.settingsUpdate, "session.settings.update model=\(selectedModel) effort=\(selectedEffort) plan=\(planModeEnabled) access=\(selectedPermissionMode)")
    }

    func refreshCodexDetection() {
        runtime.refreshDetection()
        record(.sessionList, "codex.detect installed=\(runtime.detection.isInstalled)")
    }

    func requestRuntimeInitializeAndModels() {
        if runtime.isInitialized || runtime.isInitializing {
            messages.append(ConversationMessage(role: "Tool", text: "Codex app-server already initialized or initializing."))
            return
        }
        do {
            if runtime.isReadyForAppServer {
                try runtime.startAppServer(cwd: projectCWD)
            } else if !runtime.isAppServerRunning {
                messages.append(ConversationMessage(role: "Tool", text: "Cannot start app-server. Check Codex CLI detection."))
                return
            }
            try runtime.initialize()
            messages.append(ConversationMessage(role: "Tool", text: "Codex app-server initialize + model/list requested."))
            record(.sessionStart, "codex.appServer initialize + model/list")
        } catch {
            messages.append(ConversationMessage(role: "Tool", text: "Codex runtime probe failed: \(error)"))
        }
    }

    func stopRuntime() {
        runtime.stopAppServer()
        streamingMessageID = nil
        lastAssistantTextLength = 0
        record(.sessionStop, "codex.appServer stop")
    }

    func requestRelaySnapshot() {
        let envelope = relayService.snapshotEnvelope(correlationID: UUID().uuidString)
        relaySnapshot = envelope.payload
        relayEventCount = relayService.eventCount
        relayStatusText = "snapshot.get seq=\(relaySnapshot.lastEventSeq)"
        record(.snapshotGet, "snapshot.get seq=\(relaySnapshot.lastEventSeq)")
    }

    var relayPairingDisplay: String {
        guard relayServerRunning, let pairing = relayHTTPServer.pairingPayload else {
            return "Relay not running"
        }
        let ms = Int(pairing.expiresAt.timeIntervalSinceNow)
        return """
        host: \(pairing.host)
        port: \(pairing.port)
        wsPort: \(pairing.wsPort ?? pairing.port)
        token: \(pairing.token.prefix(16))...
        claim: \(pairing.claim.prefix(16))...
        deviceID: \(pairing.deviceID ?? "-")
        expires: \(ms)s
        version: \(pairing.protocolVersion)
        """
    }

    var relayPairingURI: String {
        guard relayServerRunning, let pairing = relayHTTPServer.pairingPayload else {
            return "macrelay://pair?host=127.0.0.1&port=48731&claim="
        }
        return RelayPairingURI(payload: pairing).uriString
    }

    func rotateRelayPairing() {
        relayHTTPServer.rotatePairingToken()
        relayStatusText = "Pairing rotated port=\(relayServerPort)"
        record(.settingsUpdate, "relay.pairing.rotate")
    }

    #if os(macOS)
    var relayPairingQRImage: NSImage? {
        guard relayServerRunning, let pairing = relayHTTPServer.pairingPayload else { return nil }
        let uri = RelayPairingURI(payload: pairing).uriString
        let data = Data(uri.utf8)
        guard let qrFilter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        qrFilter.setValue(data, forKey: "inputMessage")
        qrFilter.setValue("H", forKey: "inputCorrectionLevel")
        guard let ciImage = qrFilter.outputImage else { return nil }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
    #endif

    func setRelayHost(mode: String) {
        guard mode == "local" || mode == "lan" else { return }
        relayLANIPv4 = RelayHostDetector.primaryLANIPv4()
        if mode == "lan", relayLANIPv4 == nil {
            relayServerLastError = "No LAN IPv4 found — fallback to localhost"
            relayHostMode = "local"
        } else {
            relayHostMode = mode
        }
        relayServerHost = relayHostMode == "lan" ? (relayLANIPv4 ?? "127.0.0.1") : "127.0.0.1"
        UserDefaults.standard.set(relayHostMode, forKey: relayHostModeConfigKey)

        let wasRunning = relayServerRunning
        if wasRunning {
            stopRelayServer()
        }
        if wasRunning || relayServerConfiguredToStart {
            startRelayServer(persistConfiguration: false)
        }
    }

    func startRelayServer(persistConfiguration: Bool = true) {
        relayServerLastError = nil
        do {
            try relayHTTPServer.start(host: relayServerHost, port: 0)
            try relayWSServer.start(host: relayServerHost, port: 0)
            _ = relayWSServer.waitUntilReady(timeout: 2)
            relayHTTPServer.wsServerPort = relayWSServer.port
            relayServerRunning = true
            relayServerPort = relayHTTPServer.port ?? 0
            relayServerConfiguredToStart = true
            if persistConfiguration {
                UserDefaults.standard.set(true, forKey: relayServerConfigKey)
            }
            relayStatusText = "Relay running on \(relayServerHost):\(relayServerPort)"
            record(.sessionStart, "relay.start host=\(relayServerHost) port=\(relayServerPort)")
        } catch {
            relayServerLastError = "\(error)"
            relayServerRunning = false
            relayServerConfiguredToStart = false
            relayStatusText = "Relay error: \(error)"
            if persistConfiguration {
                UserDefaults.standard.set(false, forKey: relayServerConfigKey)
            }
        }
    }

    func stopRelayServer() {
        relayHTTPServer.stop()
        relayWSServer.stop()
        relayServerRunning = false
        relayServerPort = 0
        relayServerConfiguredToStart = false
        UserDefaults.standard.set(false, forKey: relayServerConfigKey)
        relayStatusText = "Relay stopped"
        record(.sessionStop, "relay.stop")
    }

    // MARK: - Mock sendDraft

    private func sendDraftMock(_ text: String) {
        messages.append(ConversationMessage(role: "User", text: text))
        messages.append(ConversationMessage(role: "Codex", text: "Queued turn/start for \(selectedModel), \(selectedEffort), \(planModeEnabled ? "Plan" : "Act"), \(selectedPermissionMode)."))
        record(.turnStart, "session.turn.start model=\(selectedModel) effort=\(selectedEffort) access=\(selectedPermissionMode)")
    }

    // MARK: - Real sendDraft

    private func sendDraftReal(_ text: String) {
        // Clear mock messages on first real send
        if !hasStartedRealSession {
            messages.removeAll()
            hasStartedRealSession = true
        }

        messages.append(ConversationMessage(role: "User", text: text))

        // Add a streaming placeholder that will be updated by delta events
        let streamingMsg = ConversationMessage(role: "Codex", text: "…")
        streamingMessageID = streamingMsg.id
        streamingTurnID = nil
        lastAssistantTextLength = 0
        messages.append(streamingMsg)

        do {
            // enqueueDraft handles the full async chain:
            // startAppServer → initialize → model/list → thread/start → turn/start
            // Each step waits for the previous response before proceeding.
            try runtime.enqueueDraft(
                cwd: projectCWD,
                text: text,
                model: selectedModel,
                effort: selectedEffort,
                threadSandbox: threadSandboxValue,
                turnSandbox: turnSandboxValue,
                approvalPolicy: approvalPolicyValue
            )

            record(.turnStart, "session.turn.start model=\(selectedModel) effort=\(selectedEffort) access=\(selectedPermissionMode)")
        } catch {
            // Replace streaming placeholder with error
            if let idx = messages.lastIndex(where: { $0.id == streamingMessageID }) {
                messages[idx] = ConversationMessage(role: "Tool", text: "Failed to start turn: \(error)")
            }
            streamingMessageID = nil
            streamingTurnID = nil
        }
    }

    // MARK: - Snapshot → Messages Streaming

    private func handleSnapshotUpdate(_ newSnapshot: SessionSnapshot) {
        guard runtimeMode == .real else { return }
        guard let streamID = streamingMessageID else { return }

        // Stream assistant text deltas into the placeholder message
        if let turn = newSnapshot.activeTurn {
            guard let turnID = turn.id else { return }
            let expectedTurnID = streamingTurnID ?? runtime.latestTurnID
            guard expectedTurnID == turnID else {
                return
            }
            streamingTurnID = turnID

            let currentText = turn.assistantText
            if currentText.count > lastAssistantTextLength || turn.isCompleted {
                lastAssistantTextLength = currentText.count
                if let idx = messages.lastIndex(where: { $0.id == streamID }) {
                    let displayText = currentText.isEmpty ? "…" : currentText
                    replaceMessage(at: idx, with: ConversationMessage(
                        id: streamID,
                        role: "Codex",
                        text: displayText
                    ))
                }
            }

            // Turn completed — finalize
            if turn.isCompleted {
                streamingMessageID = nil
                streamingTurnID = nil
                lastAssistantTextLength = 0
            }
        }

        // Show errors — replace streaming placeholder
        if let error = newSnapshot.lastError {
            if let idx = messages.lastIndex(where: { $0.id == streamID }) {
                let errorText = error.code.map { "[\($0)] \(error.message)" } ?? error.message
                replaceMessage(at: idx, with: ConversationMessage(id: streamID, role: "Tool", text: "Error: \(errorText)"))
            }
            streamingMessageID = nil
            streamingTurnID = nil
            lastAssistantTextLength = 0
        }
    }

    private func handleLatestTurnID(_ turnID: String?) {
        guard runtimeMode == .real, streamingMessageID != nil, let turnID else { return }
        streamingTurnID = turnID
    }

    private func ingestRelayEvent(_ event: CodexAppServerEvent) {
        do {
            let events = try relayService.ingest(event)
            guard !events.isEmpty else { return }
            relaySnapshot = relayService.snapshotEnvelope().payload
            relayEventCount = relayService.eventCount
            relayStatusText = "relay seq=\(relaySnapshot.lastEventSeq) events=\(relayEventCount)"
        } catch {
            relayStatusText = "relay error: \(error)"
        }
    }

    // MARK: - Helpers

    private func setFile(_ fileID: String, state: String) {
        guard let index = files.firstIndex(where: { $0.id == fileID }) else { return }
        files[index].reviewState = state
    }

    private func replaceMessage(at index: Int, with message: ConversationMessage) {
        guard messages.indices.contains(index) else { return }
        var nextMessages = messages
        nextMessages[index] = message
        messages = nextMessages
    }

    private func record(_ type: RelayCommandType, _ detail: String) {
        commandLog.insert(RelayCommandLogEntry(type: type, detail: detail), at: 0)
        commandLog = Array(commandLog.prefix(6))
    }
}

// MARK: - Supporting Models

struct NavItem: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
}

struct ActiveRun: Identifiable {
    let id: String
    let title: String
    let profile: String
    let status: String
}

struct SessionListItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let status: String
    let count: Int
}

struct ConversationMessage: Identifiable {
    let id: UUID
    let role: String
    let text: String

    init(role: String, text: String) {
        self.id = UUID()
        self.role = role
        self.text = text
    }

    init(id: UUID, role: String, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

struct ChangedFileMock: Identifiable {
    let id: String
    let path: String
    let status: String
    let impact: String
    var reviewState: String
}

struct RelayCommandLogEntry: Identifiable {
    let id = UUID()
    let type: RelayCommandType
    let detail: String
    let createdAt = Date()
}
