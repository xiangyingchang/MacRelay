import AgentClientCore
import Combine
import Foundation
import SwiftUI

// MARK: - MacShellViewModel

@MainActor
final class MacShellViewModel: ObservableObject {
    var runtime: AgentRuntime = CodexRuntime()

    static func createRuntime(for provider: String) -> AgentRuntime {
        switch provider {
        case "Claude Code": return ClaudeCodeRuntime()
        default: return CodexRuntime()
        }
    }

    func setupRuntimeSubscriptions() {
        cancellables.removeAll()
        runtime.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)

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

        runtime.$modelNames
            .receive(on: RunLoop.main)
            .sink { [weak self] modelNames in
                self?.reconcileSelectedModel(with: modelNames)
            }
            .store(in: &cancellables)

        runtime.onEventReceived = { [weak self] event in
            Task { @MainActor in
                self?.ingestRelayEvent(event)
            }
        }

        runtime.onThreadStarted = { [weak self] threadID in
            Task { @MainActor in
                guard let self else { return }
                // If workspace already has sessions, auto-save new ones to workspace
                if !self.workspaceSessions.isEmpty {
                    self.saveSessionToWorkspace(id: threadID)
                }
                self.bindCurrentMessages(toSession: threadID)
            }
        }
    }

    func switchProvider(to provider: String) {
        runtime.stopAppServer()
        runtime = Self.createRuntime(for: provider)
        UserDefaults.standard.set(provider, forKey: "agentProvider")
        messages.removeAll()
        streamingMessageID = nil
        streamingTurnID = nil
        lastAssistantTextLength = 0
        selectedModel = ""
        runtime.refreshDetection()
        reconcileSelectedModel(with: runtime.modelNames)
        setupRuntimeSubscriptions()
    }
    let relayService = MacRelayService(
        connection: ConnectionSnapshotPayload(
            deviceID: "local-mac-ui",
            macName: ProcessInfo.processInfo.hostName,
            isPaired: true,
            isOnline: true
        )
    )

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
    private var relayWSServer: MacRelayWebSocketServer?
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
        RelayCommandLogEntry(type: .sessionStart, detail: "session.start cwd=\(FileManager.default.currentDirectoryPath)"),
        RelayCommandLogEntry(type: .snapshotGet, detail: "snapshot.get seq=8")
    ]

    /// ID of the streaming assistant message currently being built.
    /// Used to update it in-place as deltas arrive.
    private var streamingMessageID: UUID?
    /// Turn id that owns the current streaming placeholder.
    private var streamingTurnID: String?
    /// Previous assistant text length, to detect new delta content.
    private var lastAssistantTextLength = 0
    /// True while a user-created empty thread is waiting for its real thread id.
    private var isCreatingNewSession = false
    let navItems: [NavItem] = [
        NavItem(title: "Codex", symbol: "plus.bubble"),
        NavItem(title: "Sessions", symbol: "clock"),
        NavItem(title: "Models", symbol: "square.stack.3d.up"),
        NavItem(title: "Settings", symbol: "gearshape")
    ]

    /// Session IDs saved to workspace (mutually exclusive with active list).
    /// Uses @AppStorage so SwiftUI observes changes and re-renders the sidebar.
    @AppStorage("savedSessionIDs") private var _savedSessionIDsData: Data = Data()
    private var savedSessionIDs: Set<String> {
        get { (try? JSONDecoder().decode(Set<String>.self, from: _savedSessionIDsData)) ?? [] }
        set { _savedSessionIDsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// All sessions from runtime.
    var allSessionItems: [SessionListItem] {
        runtime.sessions.map { s in
            SessionListItem(
                id: s.sessionID,
                title: s.displayTitle,
                subtitle: "",
                status: s.status ?? "idle",
                count: 0
            )
        }
    }

    /// Sessions NOT saved to workspace (shown in "会话" list).
    var activeSessions: [SessionListItem] {
        allSessionItems.filter { !savedSessionIDs.contains($0.id) }
    }

    /// Sessions saved to workspace (shown under "空间").
    var workspaceSessions: [SessionListItem] {
        allSessionItems.filter { savedSessionIDs.contains($0.id) }
    }

    var displaySessions: [SessionListItem] { allSessionItems }

    @Published var messages: [ConversationMessage] = []

    private var messageCache = SessionMessageCache<ConversationMessage>()

    @Published var files: [ChangedFileMock] = [
        ChangedFileMock(id: "mac-shell", path: "Sources/AgentClientMacShell/main.swift", status: "Modified", impact: "+420 -360", reviewState: "Pending"),
        ChangedFileMock(id: "ui-doc", path: "产品/AI 编程 CLI 客户端 UI 设计基准.md", status: "Updated", impact: "+54 -0", reviewState: "Approved"),
        ChangedFileMock(id: "plan", path: "产品/AI 编程 CLI 客户端落地执行计划.md", status: "Updated", impact: "+31 -0", reviewState: "Pending")
    ]

    let fallbackModels: [String] = []
    let efforts = ["low", "medium", "high", "xhigh"]
    /// Assistant display name based on the active provider.
    var assistantName: String {
        UserDefaults.standard.string(forKey: "agentProvider") == "Claude Code" ? "Claude" : "Codex"
    }
    let permissions = ["Read Only", "Default", "Full Access"]
    private var cancellables = Set<AnyCancellable>()

    var activeSession: SessionListItem {
        displaySessions.first { $0.id == activeRunID }
            ?? displaySessions.first
            ?? SessionListItem(id: "", title: "No session", subtitle: "", status: "idle", count: 0)
    }

    var selectedFile: ChangedFileMock {
        files.first { $0.id == selectedFileID } ?? files[0]
    }

    var displayFiles: [ChangedFileMock] {
        runtime.snapshot.fileChanges.values
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
        if let realApproval = runtime.snapshot.pendingApprovals.values.first(where: { $0.isPending }) {
            return RelayApprovalPayload(approval: realApproval)
        }
        return nil
    }

    var modelOptions: [String] {
        runtime.modelNames.isEmpty ? fallbackModels : runtime.modelNames
    }

    var runtimeStatusTone: StatusPill.Tone {
        runtime.cliInstalled ? .success : .warning
    }

    /// Session status text derived from runtime.snapshot.
    var sessionStatusText: String {
        switch runtime.snapshot.status {
        case .idle: return "Idle"
        case .active:
            if runtime.snapshot.pendingApprovals.values.contains(where: { $0.isPending }) {
                return "Waiting"
            }
            if let turn = runtime.snapshot.activeTurn, !turn.isCompleted {
                return turn.assistantText.isEmpty ? "Running" : "Streaming"
            }
            return "Running"
        case .waitingOnApproval: return "Waiting"
        case .systemError: return "Error"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .exited: return "Exited"
        }
    }

    /// Session status pill color derived from runtime.snapshot.
    var sessionStatusTone: StatusPill.Tone {
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

    /// Journal for session transcripts and project memory.
    let journal = SessionJournal()

    /// User-selected workspace directory. Defaults to home directory.
    /// Used as the CWD when starting app-server / Claude Code.
    private let workspaceCWDKey = "MacShellWorkspaceCWD"

    @Published var workspaceCWD: String = {
        // Restore last workspace from UserDefaults
        if let saved = UserDefaults.standard.string(forKey: "MacShellWorkspaceCWD"),
           FileManager.default.fileExists(atPath: saved) {
            return saved
        }
        let cwd = FileManager.default.currentDirectoryPath
        if FileManager.default.fileExists(atPath: cwd) { return cwd }
        return NSHomeDirectory()
    }() {
        didSet {
            UserDefaults.standard.set(workspaceCWD, forKey: workspaceCWDKey)
            journal.workspacePath = workspaceCWD
        }
    }

    var projectCWD: String { workspaceCWD }
    /// Last path component of the workspace directory (for sidebar display).
    var workspaceFolderName: String {
        URL(fileURLWithPath: workspaceCWD).lastPathComponent
    }

    /// Open a system folder picker and update workspaceCWD.
    func selectWorkspace() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "选择 Claude Code 的工作目录"
        panel.directoryURL = URL(fileURLWithPath: workspaceCWD)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspaceCWD = url.path
        // Auto-load previous sessions, then start a fresh session
        loadPreviousSessionMessages()
        startNewSession()
        #endif
    }

    /// Load archived sessions from .macrelay/sessions/ into the sidebar list.
    func loadPreviousSessionMessages() {
        let archived = journal.loadArchivedSessions()
        guard !archived.isEmpty else { return }

        // Register each archived session in the sidebar
        for session in archived {
            if !runtime.sessions.contains(where: { $0.sessionID == session.sessionID }) {
                let info = RelaySessionInfoPayload(
                    sessionID: session.sessionID,
                    cwd: workspaceCWD,
                    model: "",
                    effort: "",
                    status: "completed",
                    createdAt: session.createdAt,
                    title: session.messages.first(where: { $0.role == "User" })?.text
                )
                runtime.sessions.append(info)
            }
        }

        // Load the most recent session's messages into the conversation view
        if let last = archived.last {
            messages = last.messages.map { role, text in
                ConversationMessage(role: role, text: text)
            }
        }
    }

    /// Select an archived (disk-based) session — load its messages from the log file.
    func selectArchivedSession(sessionID: String) {
        let entries = journal.loadArchivedSessionMessages(sessionID: sessionID)
        messages = entries.map { role, text in
            ConversationMessage(role: role, text: text)
        }
    }

    /// Delete an archived session (remove from list + delete log file).
    func deleteSession(id: String) {
        var saved = savedSessionIDs
        saved.remove(id)
        savedSessionIDs = saved
        runtime.sessions.removeAll(where: { $0.sessionID == id })
        journal.deleteArchivedSession(sessionID: id)
    }

    /// Save a session to workspace (moves from active list to workspace list).
    func saveSessionToWorkspace(id: String) {
        var saved = savedSessionIDs
        saved.insert(id)
        savedSessionIDs = saved
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

    private let modelConfigKey = "MacShellSelectedModel"
    private let effortConfigKey = "MacShellSelectedEffort"
    private let planModeConfigKey = "MacShellPlanMode"
    private let permissionConfigKey = "MacShellPermissionMode"

    init() {
        self.selectedModel = UserDefaults.standard.string(forKey: modelConfigKey) ?? "gpt-5.5"
        self.selectedEffort = UserDefaults.standard.string(forKey: effortConfigKey) ?? "low"
        self.planModeEnabled = UserDefaults.standard.bool(forKey: planModeConfigKey)
        self.selectedPermissionMode = UserDefaults.standard.string(forKey: permissionConfigKey) ?? "Read Only"
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

        // Switch to stored provider if not Codex CLI
        let storedProvider = UserDefaults.standard.string(forKey: "agentProvider") ?? "Codex CLI"
        if storedProvider != "Codex CLI" {
            runtime = Self.createRuntime(for: storedProvider)
        }

        if relayServerConfiguredToStart {
            startRelayServer(persistConfiguration: false)
        }

        // Restore last workspace and load previous conversations
        journal.workspacePath = workspaceCWD
        loadPreviousSessionMessages()

        setupRuntimeSubscriptions()
        runtime.refreshDetection()
        reconcileSelectedModel(with: runtime.modelNames)
    }

    // MARK: - Actions

    /// Start a fresh session: clear current thread, create a new one,
    /// and clear the conversation view.
    func startNewSession() {
        saveActiveSessionMessages()
        // Immediate visual feedback — clear conversation before the async chain runs
        messages = messageCache.beginPendingNewSession()
        streamingMessageID = nil
        streamingTurnID = nil
        lastAssistantTextLength = 0
        isCreatingNewSession = true
        do {
            // Just initialize the app-server and fetch models — don't enqueue a draft.
            // The user's first real message will create the thread + turn.
            runtime.clearCurrentThread()
            if !runtime.isAppServerRunning {
                try runtime.startAppServer(cwd: projectCWD)
            }
            if !runtime.isInitialized, !runtime.isInitializing {
                try runtime.initialize()
            }
            record(.sessionStart, "session.start cwd=\(projectCWD)")
        } catch {
            isCreatingNewSession = false
            messages.append(ConversationMessage(role: "Tool", text: "Failed to start new session: \(error)"))
        }
    }

    /// Switch to an existing session: update runtime, clear conversation,
    /// and show a confirmation message.
    func selectSession(id: String) {
        saveActiveSessionMessages()
        // Check if this is an archived session (date-prefixed ID from .macrelay/sessions/)
        if id.contains("-"), id.count >= 14 {
            selectArchivedSession(sessionID: id)
            activeRunID = id
            return
        }
        do {
            try runtime.selectSession(sessionID: id)
        } catch {
            messages.append(ConversationMessage(role: "Tool", text: "Failed to select session: \(error)"))
            return
        }
        activeRunID = id
        messages = messageCache.messages(for: id)
        isCreatingNewSession = false
        streamingMessageID = nil
        streamingTurnID = nil
        lastAssistantTextLength = 0
        record(.sessionStart, "session.select id=\(id)")
    }

    func sendDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        sendDraftReal(trimmed)
        draftText = ""
    }

    func approveCommand() {
        if let (_, approval) = runtime.snapshot.pendingApprovals.first(where: { $0.value.isPending }) {
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
        if let (_, approval) = runtime.snapshot.pendingApprovals.first(where: { $0.value.isPending }) {
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
        // Persist to UserDefaults
        UserDefaults.standard.set(selectedModel, forKey: modelConfigKey)
        UserDefaults.standard.set(selectedEffort, forKey: effortConfigKey)
        UserDefaults.standard.set(planModeEnabled, forKey: planModeConfigKey)
        UserDefaults.standard.set(selectedPermissionMode, forKey: permissionConfigKey)

        // Send thread/settings/update when app-server is initialized
        // and a thread exists. Otherwise silently skip — the settings will be
        // applied at thread/start or turn/start time via enqueueDraft.
        if runtime.isInitialized, runtime.currentThreadID != nil {
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
        record(.sessionList, "codex.detect installed=\(runtime.cliInstalled)")
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
        let wasRunning = relayServerRunning
        if wasRunning {
            stopRelayServer(persistConfigurationChange: false)
            startRelayServer(persistConfiguration: false)
        }
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
            relayWSServer?.stop()
            try relayHTTPServer.start(host: relayServerHost, port: 0)
            let dispatcher = MacRelayRuntimeCommandDispatcher(
                runtime: runtime,
                defaultCWD: { self.projectCWD }
            )
            let wsServer = MacRelayWebSocketServer(
                relayService: relayService,
                pairingToken: relayHTTPServer.token,
                commandDispatcher: dispatcher
            )
            try wsServer.start(host: relayServerHost, port: 0)
            _ = wsServer.waitUntilReady(timeout: 2)
            relayWSServer = wsServer
            relayHTTPServer.wsServerPort = wsServer.port
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
        stopRelayServer(persistConfigurationChange: true)
    }

    private func stopRelayServer(persistConfigurationChange: Bool) {
        relayHTTPServer.stop()
        relayWSServer?.stop()
        relayWSServer = nil
        relayServerRunning = false
        relayServerPort = 0
        relayServerConfiguredToStart = false
        if persistConfigurationChange {
            UserDefaults.standard.set(false, forKey: relayServerConfigKey)
        }
        relayStatusText = "Relay stopped"
        record(.sessionStop, "relay.stop")
    }

    // MARK: - Mock sendDraft

    private func sendDraftReal(_ text: String) {
        messages.append(ConversationMessage(role: "User", text: text))
        journal.logUserMessage(text)

        // Add a streaming placeholder that will be updated by delta events
        let streamingMsg = ConversationMessage(role: assistantName, text: "…")
        streamingMessageID = streamingMsg.id
        streamingTurnID = nil
        lastAssistantTextLength = 0
        messages.append(streamingMsg)
        saveActiveSessionMessages()

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
                saveActiveSessionMessages()
            }
            streamingMessageID = nil
            streamingTurnID = nil
        }
    }

    // MARK: - Snapshot → Messages Streaming

    private func handleSnapshotUpdate(_ newSnapshot: SessionSnapshot) {
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
                        role: assistantName,
                        text: displayText
                    ))
                }
            }

            // Turn completed — finalize and log to journal
            if turn.isCompleted {
                streamingMessageID = nil
                streamingTurnID = nil
                lastAssistantTextLength = 0
                journal.logAssistantMessage(assistantName, currentText)
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
        guard streamingMessageID != nil, let turnID else { return }
        streamingTurnID = turnID
    }

    private func reconcileSelectedModel(with modelNames: [String]) {
        guard let first = modelNames.first else { return }
        if selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !modelNames.contains(selectedModel) {
            selectedModel = first
            UserDefaults.standard.set(first, forKey: modelConfigKey)
        }
    }

    private func ingestRelayEvent(_ event: CodexAppServerEvent) {
        // Remote turn/started — inject user message into Mac UI when the turn
        // came from an iOS client (streamingMessageID is nil because sendDraftReal
        // wasn't called locally).
        if case let .notification(method, params) = event, method == "turn/started",
           let input = params?["input"] as? String, !input.isEmpty,
           streamingMessageID == nil {
            messages.append(ConversationMessage(role: "User", text: input))
            let streamingMsg = ConversationMessage(role: assistantName, text: "…")
            streamingMessageID = streamingMsg.id
            streamingTurnID = nil
            lastAssistantTextLength = 0
            messages.append(streamingMsg)
            saveActiveSessionMessages()
        }

        do {
            let events = try relayService.ingest(event)
            guard !events.isEmpty else { return }
            relaySnapshot = relayService.snapshotEnvelope().payload
            relayEventCount = relayService.eventCount
            relayStatusText = "relay seq=\(relaySnapshot.lastEventSeq) events=\(relayEventCount)"
            // Active push to all connected WebSocket clients
            var snapshotEnvelope = relayService.snapshotEnvelope()
            // Inject available sessions from runtime
            if !runtime.sessions.isEmpty {
                snapshotEnvelope.payload.availableSessions = runtime.sessions
            }
            if let data = try? JSONEncoder().encode(snapshotEnvelope) {
                relayWSServer?.broadcast(data: data)
                print("[Relay] broadcast snapshot seq=\(relaySnapshot.lastEventSeq) type=\(events.last?.type ?? "?")")
            }
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
        saveActiveSessionMessages()
    }

    private func saveActiveSessionMessages() {
        if isCreatingNewSession {
            messageCache.savePending(messages)
            return
        }
        guard runtime.sessions.contains(where: { $0.sessionID == activeRunID }) else { return }
        messageCache.save(messages: messages, for: activeRunID)
    }

    private func bindCurrentMessages(toSession threadID: String) {
        if isCreatingNewSession {
            activeRunID = threadID
            messages = messageCache.bindPendingNewSession(threadID: threadID, currentMessages: messages)
            isCreatingNewSession = false
            return
        }
        if activeRunID != threadID {
            saveActiveSessionMessages()
            activeRunID = threadID
        }
        messageCache.save(messages: messages, for: threadID)
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

struct SessionMessageCache<Message> {
    private var histories: [String: [Message]] = [:]
    private var pendingNewSession: [Message]?

    mutating func beginPendingNewSession() -> [Message] {
        pendingNewSession = []
        return []
    }

    mutating func savePending(_ messages: [Message]) {
        pendingNewSession = messages
    }

    mutating func bindPendingNewSession(threadID: String, currentMessages: [Message]) -> [Message] {
        let messages = pendingNewSession ?? currentMessages
        histories[threadID] = messages
        pendingNewSession = nil
        return messages
    }

    mutating func save(messages: [Message], for sessionID: String) {
        histories[sessionID] = messages
    }

    func messages(for sessionID: String) -> [Message] {
        histories[sessionID] ?? []
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
