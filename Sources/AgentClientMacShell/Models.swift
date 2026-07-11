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
        case "OpenAI": return APIAgentRuntime(provider: .openAI)
        case "DeepSeek": return APIAgentRuntime(provider: .deepSeek)
        case "MIMO": return APIAgentRuntime(provider: .mimo)
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

        runtime.$currentSteps
            .receive(on: RunLoop.main)
            .sink { [weak self] steps in
                self?.handleStepUpdate(steps)
            }
            .store(in: &cancellables)

        bindRuntimeLifecycleCallbacks()
    }

    /// Runtime instances are replaced on provider switch. Keep every direct
    /// callback assignment in one repeatable binding step so a new provider
    /// cannot lose session success/failure lifecycle delivery.
    private func bindRuntimeLifecycleCallbacks() {
        RuntimeLifecycleBinder.bind(
            runtime: runtime,
            onEvent: { [weak self] event in
                Task { @MainActor in self?.ingestRelayEvent(event) }
            },
            onThreadStarted: { [weak self] threadID in
                Task { @MainActor in
                    guard let self else { return }
                    let continuedArchivedID = self.continuingArchivedSessionID
                    self.bindCurrentMessages(toSession: threadID)
                    if continuedArchivedID != nil {
                        self.saveSessionToWorkspace(id: threadID)
                    } else if self.shouldAutoSaveNewSessionsToWorkspace {
                        self.saveSessionToWorkspace(id: threadID)
                    }
                }
            },
            onSessionStartFailed: { [weak self] _ in
                Task { @MainActor in self?.rollbackNewSession() }
            }
        )
    }

    func switchProvider(to provider: String) {
        runtime.stopAppServer()
        runtime = Self.createRuntime(for: provider)
        // Bind the replacement before any detection/initialization work can
        // synchronously or asynchronously emit lifecycle events.
        setupRuntimeSubscriptions()
        UserDefaults.standard.set(provider, forKey: "agentProvider")
        messages.removeAll()
        streamingMessageID = nil
        streamingTurnID = nil
        lastAssistantTextLength = 0
        selectedModel = ""
        runtime.refreshDetection()
        reconcileSelectedModel(with: runtime.modelNames)
        // Provider is UI-owned state. Publish it immediately instead of waiting
        // for a model-list event, which may never arrive before an iOS snapshot.
        syncSettingsToRelay()
        broadcastGroupedSnapshot()
    }
    let relayService = MacRelayService(
        connection: ConnectionSnapshotPayload(
            deviceID: "local-mac-ui",
            macName: ProcessInfo.processInfo.hostName,
            isPaired: true,
            isOnline: true
        )
    )

    /// Run history store for querying past runs.
    lazy var runHistoryStore: RunHistoryStore = FileRunHistoryStore()

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
    @Published private(set) var relayPhoneConnected = false
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
    @Published var activeRunID = "run-polish" {
        didSet {
            if !activeRunID.isEmpty && activeRunID != oldValue {
                setupTraceWriter()
                refreshTimeline()
            }
        }
    }

    /// Timeline items for the current session, derived from RuntimeEvents.
    /// UI consumers should read this instead of accessing runtimeEvents directly.
    @Published private(set) var timelineItems: [TimelineItem] = []
    @Published var activeNav = "Codex"
    @Published var selectedModel: String
    @Published var selectedEffort = "low"
    @Published var selectedPermissionMode = "Read Only"
    @Published var planModeEnabled = true
    @Published var draftText = ""
    @Published var selectedFileID = "mac-shell"
    @Published var commandApprovalVisible = true
    @Published private var archivedSessionItems: [SessionListItem] = []
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
    private var continuingArchivedSessionID: String?
    /// Tracks how much of the streaming text has been scanned for steps.
    private var parsedTextLength = 0
    /// Returns the session ID that is currently streaming, or nil if idle.
    var streamingSessionID: String? {
        streamingMessageID != nil ? activeRunID : nil
    }
    let navItems: [NavItem] = [
        NavItem(title: "Codex", symbol: "plus.bubble"),
        NavItem(title: "Sessions", symbol: "clock"),
        NavItem(title: "Models", symbol: "square.stack.3d.up"),
        NavItem(title: "Settings", symbol: "gearshape")
    ]

    /// Session IDs saved to the current workspace (mutually exclusive with active list).
    /// The storage key is workspace-scoped; using one global key made sessions
    /// from different folders bleed into each other's sidebar groups.
    private let legacySavedSessionIDsKey = "savedSessionIDs"
    private var savedSessionIDs: Set<String> {
        get {
            guard let data = UserDefaults.standard.data(forKey: savedSessionIDsStorageKey) else {
                return []
            }
            return (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
        }
        set {
            let data = (try? JSONEncoder().encode(newValue)) ?? Data()
            UserDefaults.standard.set(data, forKey: savedSessionIDsStorageKey)
            objectWillChange.send()
        }
    }

    private var savedSessionIDsStorageKey: String {
        "savedSessionIDs.\(Self.workspaceStorageComponent(for: workspaceCWD))"
    }

    private var shouldAutoSaveNewSessionsToWorkspace: Bool {
        !savedSessionIDs.isEmpty || !archivedSessionItems.isEmpty
    }

    private static func workspaceStorageComponent(for path: String) -> String {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let encoded = Data(normalized.utf8).base64EncodedString()
        return encoded
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Runtime sessions plus local archived transcripts.
    var allSessionItems: [SessionListItem] {
        let runtimeItems = runtime.sessions.map { s in
            SessionListItem(
                id: s.sessionID,
                title: s.displayTitle,
                subtitle: "",
                status: s.status ?? "idle",
                count: 0
            )
        }
        let runtimeIDs = Set(runtime.sessions.map(\.sessionID))
        let result = runtimeItems + archivedSessionItems.filter { !runtimeIDs.contains($0.id) }
        return result
    }

    /// Sessions NOT saved to workspace (shown in "会话" list).
    var activeSessions: [SessionListItem] {
        let grouping = workspaceSessionGrouper
        return allSessionItems.filter { !grouping.isWorkspaceSession($0.id) }
    }

    /// Sessions saved to workspace (shown under "空间").
    var workspaceSessions: [SessionListItem] {
        let grouping = workspaceSessionGrouper
        return allSessionItems.filter { grouping.isWorkspaceSession($0.id) }
    }

    var displaySessions: [SessionListItem] { allSessionItems }

    private var workspaceSessionGrouper: WorkspaceSessionGrouper {
        WorkspaceSessionGrouper(
            workspaceCWD: workspaceCWD,
            savedSessionIDs: savedSessionIDs,
            archivedSessionIDs: Set(archivedSessionItems.map(\.id)),
            runtimeSessionCWDs: Dictionary(uniqueKeysWithValues: runtime.sessions.map { ($0.sessionID, $0.cwd) })
        )
    }

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

    /// Configure trace persistence for the current active run.
    private func setupTraceWriter() {
        guard !workspaceCWD.isEmpty, !activeRunID.isEmpty else { return }
        let baseDir = URL(fileURLWithPath: workspaceCWD)
            .appendingPathComponent(".macrelay/sessions")
        relayService.traceWriter = TraceWriter(
            runID: activeRunID,
            sessionID: runtime.currentThreadID,
            baseDirectory: baseDir
        )
    }

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
        runtime.clearCurrentThread()
        runtime.sessions.removeAll()
        archivedSessionItems = []
        messageCache.clear()
        messages = []
        activeRunID = ""
        // Auto-load previous sessions, then start a fresh session
        loadPreviousSessionMessages()
        startNewSession()
        #endif
    }

    /// Load archived sessions from .macrelay/sessions/ into the sidebar list.
    func loadPreviousSessionMessages() {
        let archived = journal.loadArchivedSessions()
        let archivedIDs = Set(archived.map(\.sessionID))
        migrateLegacySavedSessionsIfNeeded(existingSessionIDs: archivedIDs)
        guard !archived.isEmpty else {
            archivedSessionItems = []
            restoreSavedRuntimeSessions(archivedIDs: [])
            return
        }

        archivedSessionItems = archived.map { session in
            SessionListItem(
                id: session.sessionID,
                title: session.messages.first(where: { $0.role == "User" })?.text ?? session.sessionID,
                subtitle: "",
                status: "completed",
                count: session.messages.count
            )
        }

        // Auto-save ALL archived sessions to workspace — they belong to this project.
        var allSaved = savedSessionIDs
        for id in archivedIDs { allSaved.insert(id) }
        savedSessionIDs = allSaved

        // Register archived sessions in runtime so listSessions() returns them
        // (used by iOS fetchSessions and WebSocket session.list handler).
        for session in archived {
            runtime.rememberSession(
                sessionID: session.sessionID,
                cwd: workspaceCWD,
                title: session.messages.first(where: { $0.role == "User" })?.text,
                status: "completed"
            )
        }

        restoreSavedRuntimeSessions(archivedIDs: archivedIDs)

        // Load the most recent session's messages into the conversation view
        if let last = archived.last {
            messages = last.messages.map { role, text in
                ConversationMessage(role: role, text: text)
            }
        }
    }

    /// Select an archived (disk-based) session — load its messages from the log file.
    func selectArchivedSession(sessionID: String) {
        runtime.clearCurrentThread()
        continuingArchivedSessionID = sessionID
        // Prefer JSON format with steps, fallback to markdown
        let loaded = journal.loadArchivedMessagesWithSteps(sessionID: sessionID)
        messages = loaded.isEmpty
            ? journal.loadArchivedSessionMessages(sessionID: sessionID).map { ConversationMessage(role: $0.role, text: $0.text) }
            : loaded
        isCreatingNewSession = false
        streamingMessageID = nil
        streamingTurnID = nil
        lastAssistantTextLength = 0
        parsedTextLength = 0
    }

    /// Delete an archived session (remove from list + delete log file).
    func deleteSession(id: String) {
        var saved = savedSessionIDs
        saved.remove(id)
        savedSessionIDs = saved
        runtime.sessions.removeAll(where: { $0.sessionID == id })
        archivedSessionItems.removeAll(where: { $0.id == id })
        journal.deleteArchivedSession(sessionID: id)
        broadcastGroupedSnapshot()
    }

    /// Save a session to workspace (moves from active list to workspace list).
    func saveSessionToWorkspace(id: String) {
        saveActiveSessionMessages()
        var saved = savedSessionIDs
        saved.insert(id)
        savedSessionIDs = saved
        broadcastGroupedSnapshot()
    }

    private func migrateLegacySavedSessionsIfNeeded(existingSessionIDs: Set<String>) {
        guard UserDefaults.standard.data(forKey: savedSessionIDsStorageKey) == nil else { return }
        guard let legacyData = UserDefaults.standard.data(forKey: legacySavedSessionIDsKey),
              let legacyIDs = try? JSONDecoder().decode(Set<String>.self, from: legacyData)
        else {
            savedSessionIDs = []
            return
        }
        savedSessionIDs = legacyIDs.intersection(existingSessionIDs)
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
        // Pre-populate the relay service so iOS gets the correct provider
        // on the very first snapshot — no wait for onAuthenticatedCountChanged.
        relayService.provider = storedProvider

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
        prepareForNewSession()
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

    /// Isolate a newly requested thread from the currently selected
    /// transcript. Both the Mac button and iOS session.start must pass through
    /// this transition before thread/started binds the real thread ID.
    private func prepareForNewSession() {
        saveActiveSessionMessages()
        messages = messageCache.beginPendingNewSession()
        streamingMessageID = nil
        streamingTurnID = nil
        lastAssistantTextLength = 0
        isCreatingNewSession = true
    }

    /// Restore the previously active transcript when the runtime rejects the
    /// asynchronous thread creation after session.start was accepted.
    private func rollbackNewSession() {
        guard isCreatingNewSession else { return }
        messageCache.cancelPendingNewSession()
        messages = SessionTranscriptRestorer.restore(
            cached: messageCache.messages(for: activeRunID),
            archivedWithSteps: journal.loadArchivedMessagesWithSteps(sessionID: activeRunID),
            archivedPlain: journal.loadArchivedSessionMessages(sessionID: activeRunID).map {
                ConversationMessage(role: $0.role, text: $0.text)
            }
        )
        // session.start cleared the runtime's current thread before the async
        // request failed. Re-select the previous session so the restored UI
        // transcript and the next turn target remain consistent.
        try? runtime.selectSession(sessionID: activeRunID)
        streamingMessageID = nil
        streamingTurnID = nil
        lastAssistantTextLength = 0
        isCreatingNewSession = false
    }

    /// Switch to an existing session: update runtime, clear conversation,
    /// and show a confirmation message.
    func selectSession(id: String) {
        saveActiveSessionMessages()
        // Archived sessions (from .macrelay/sessions/) are NOT in runtime.sessions.
        // Runtime sessions (active or saved to workspace) ARE in runtime.sessions.
        if archivedSessionItems.contains(where: { $0.id == id }) && !runtime.sessions.contains(where: { $0.sessionID == id }) {
            selectArchivedSession(sessionID: id)
            activeRunID = id
            return
        }
        // Always update activeRunID and clear streaming state, even if the
        // runtime doesn't know about this session yet (race condition:
        // sessionStart creates the thread async, sessionSelect may arrive
        // before thread/start response).
        activeRunID = id
        isCreatingNewSession = false
        streamingMessageID = nil
        streamingTurnID = nil
        lastAssistantTextLength = 0
        do {
            try runtime.selectSession(sessionID: id)
        } catch {
            // Session not in runtime yet — clear messages and wait for
            // thread/started notification to populate the session.
            messages = []
            record(.sessionStart, "session.select id=\(id) (deferred)")
            return
        }
        let cached = messageCache.messages(for: id)
        if !cached.isEmpty {
            messages = cached
        } else {
            // Try loading from archived log; fall back to empty
            let archived = journal.loadArchivedSessionMessages(sessionID: id)
            messages = archived.isEmpty ? [] : archived.map { ConversationMessage(role: $0.role, text: $0.text) }
        }
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

        // Sync UI settings to relay service for broadcast to iOS clients
        syncSettingsToRelay()
        // Broadcast updated snapshot so iOS picks up the changes immediately
        broadcastGroupedSnapshot()
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

    /// Sync current view model settings into MacRelayService so snapshot
    /// broadcasts to iOS carry the correct model, effort, planMode, permissionMode.
    func syncSettingsToRelay() {
        let currentProvider = UserDefaults.standard.string(forKey: "agentProvider") ?? "Codex CLI"
        relayService.updateSnapshotSettings(
            model: selectedModel.isEmpty ? nil : selectedModel,
            effort: selectedEffort.isEmpty ? nil : selectedEffort,
            provider: currentProvider,
            approvalPolicy: approvalPolicyValue,
            sandboxType: turnSandboxValue,
            cwd: projectCWD
        )
        relayService.updateSnapshotAvailableModels(runtime.modelNames.isEmpty ? nil : runtime.modelNames)
        relayService.planMode = planModeEnabled
        relayService.permissionMode = selectedPermissionMode
        relayService.provider = currentProvider
    }

    /// Build session lists grouped by workspace for iOS broadcast.
    /// - activeSessions → "会话": runtime sessions NOT saved to workspace
    /// - workspaceSessions → "空间": saved runtime sessions + archived sessions
    private func buildGroupedSessionLists() -> (activeSessions: [RelaySessionInfoPayload], workspaceSessions: [RelaySessionInfoPayload]) {
        var active: [RelaySessionInfoPayload] = []
        var workspace: [RelaySessionInfoPayload] = []
        let saved = savedSessionIDs
        for s in runtime.sessions {
            if saved.contains(s.sessionID) {
                workspace.append(s)
            } else {
                active.append(s)
            }
        }
        for item in archivedSessionItems {
            if !runtime.sessions.contains(where: { $0.sessionID == item.id }) {
                workspace.append(RelaySessionInfoPayload(
                    sessionID: item.id,
                    cwd: workspaceCWD,
                    model: "",
                    effort: "",
                    status: "completed",
                    createdAt: nil,
                    title: item.title
                ))
            }
        }
        return (active, workspace)
    }

    /// Broadcast the current grouped session lists to all connected iOS clients.
    private func broadcastGroupedSnapshot() {
        var snapshotEnvelope = relayService.snapshotEnvelope()
        let groups = buildGroupedSessionLists()
        snapshotEnvelope.payload.availableSessions = groups.activeSessions
        snapshotEnvelope.payload.workspaceSessions = groups.workspaceSessions
        // Align activeSessionID with the Mac VM's activeRunID.
        // relayService.snapshot.threadID may lag behind after session.select
        // because the reducer only updates it on thread/started events.
        snapshotEnvelope.payload.activeSessionID = activeRunID
        snapshotEnvelope.payload.session?.threadID = activeRunID
        // Inject current session messages into the snapshot so iOS can display them.
        // Always set — including empty array for newly created sessions.
        let recentMessages = messages.map {
            RelayConversationMessagePayload(role: $0.role, text: $0.text)
        }
        snapshotEnvelope.payload.session?.messages = recentMessages
        let totalActive = groups.activeSessions.count
        let totalWorkspace = groups.workspaceSessions.count
        if let data = try? JSONEncoder().encode(snapshotEnvelope) {
            relayWSServer?.broadcast(data: data)
            print("[Relay] broadcast snapshot active=\(totalActive) ws=\(totalWorkspace)")
        }
    }

    // MARK: - Timeline

    /// Current runtime identifier based on the selected provider.
    private var currentRuntimeIdentifier: RuntimeIdentifier {
        let provider = UserDefaults.standard.string(forKey: "agentProvider") ?? "Codex CLI"
        switch provider {
        case "Claude Code": return .claudeCode
        case "Codex CLI": return .codex
        default: return RuntimeIdentifier.from(provider)
        }
    }

    /// Refresh timeline items from the relay service's RuntimeEvent log.
    private func refreshTimeline() {
        timelineItems = relayService.timeline(runID: activeRunID)
    }

    func startRelayServer(persistConfiguration: Bool = true) {
        relayServerLastError = nil
        do {
            relayWSServer?.stop()
            try relayHTTPServer.start(host: relayServerHost, port: 0)
            var dispatcher = MacRelayRuntimeCommandDispatcher(
                runtime: runtime,
                defaultCWD: { self.projectCWD },
                onSettingsUpdate: { [weak self] planMode, permissionMode, provider in
                    Task { @MainActor in
                        guard let self else { return }
                        if let planMode { self.planModeEnabled = planMode }
                        if let permissionMode { self.selectedPermissionMode = permissionMode }
                        if let provider {
                            self.switchProvider(to: provider)
                            // Broadcast to iOS when new provider's model list arrives
                            self.runtime.$modelNames
                                .dropFirst()
                                .filter { !$0.isEmpty }
                                .first()
                                .receive(on: RunLoop.main)
                                .sink { [weak self] _ in
                                    self?.recordSettingsUpdate()
                                }
                                .store(in: &self.cancellables)
                        } else {
                            // Persist and broadcast updated settings to iOS
                            self.recordSettingsUpdate()
                        }
                    }
                },
                onSaveSessionToWorkspace: { [weak self] sessionID in
                    Task { @MainActor in
                        self?.saveSessionToWorkspace(id: sessionID)
                    }
                },
                onRemoveSessionFromWorkspace: { [weak self] sessionID in
                    Task { @MainActor in
                        self?.deleteSession(id: sessionID)
                    }
                }
            )
            // Wire onSnapshotGet so snapshot.get responses include grouped session lists
            dispatcher.onSnapshotGet = { [weak self] in
                guard let self else { return nil }
                // snapshot.get is the authoritative initial sync after pairing.
                // Refresh UI-owned settings before the server builds its envelope.
                syncSettingsToRelay()
                let groups = buildGroupedSessionLists()
                return (availableSessions: groups.activeSessions, workspaceSessions: groups.workspaceSessions)
            }
            // Wire onSessionSelect so iOS session.select loads messages from cache/journal.
            // MUST be synchronous — the dispatcher already runs on the main queue,
            // and iOS calls refresh() immediately after sessionSelect returns.
            dispatcher.onSessionSelect = { [weak self] sessionID in
                self?.selectSession(id: sessionID)
            }
            // iOS session.start creates the runtime thread directly through
            // the dispatcher, so mirror the Mac new-session state transition.
            // Without this, thread/started binds the old transcript to the new ID.
            dispatcher.onSessionStart = { [weak self] in
                self?.prepareForNewSession()
            }
            // Wire onGetMessages so snapshot.get includes current conversation messages
            dispatcher.onGetMessages = { [weak self] in
                guard let self else { return [] }
                return messages.map { RelayConversationMessagePayload(role: $0.role, text: $0.text) }
            }
            // Wire onGetActiveSessionID so snapshot.get uses the Mac VM's activeRunID
            // instead of the potentially stale relayService.snapshot.threadID.
            dispatcher.onGetActiveSessionID = { [weak self] in
                self?.activeRunID
            }
            // — no additional code between dispatcher init and wsServer —
            let wsServer = MacRelayWebSocketServer(
                relayService: relayService,
                pairingToken: relayHTTPServer.token,
                commandDispatcher: dispatcher
            )
            // Track phone connection state via WebSocket auth count
            wsServer.onAuthenticatedCountChanged = { [weak self] count in
                Task { @MainActor in
                    guard let self else { return }
                    self.relayPhoneConnected = count > 0
                    if count > 0 {
                        // New phone connected — sync current Mac settings so iOS
                        // gets the correct model/effort/planMode/permissionMode
                        // on the very first snapshot broadcast.
                        self.syncSettingsToRelay()
                        self.broadcastGroupedSnapshot()
                    }
                }
            }
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
        relayPhoneConnected = false
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

        if let error = newSnapshot.lastError {
            let errorText = error.code.map { "[\($0)] \(error.message)" } ?? error.message
            replaceStreamingMessage(streamID, with: errorText)
            return
        }

        if newSnapshot.status == .exited || newSnapshot.hasExited {
            replaceStreamingMessage(
                streamID,
                with: "Runtime exited before a response was received. Try starting a new session and check the runtime status."
            )
            return
        }

        if newSnapshot.status == .systemError || newSnapshot.status == .failed {
            let message = newSnapshot.lastError?.message ?? "Runtime failed before a response was received."
            replaceStreamingMessage(streamID, with: message)
            return
        }

        // Stream assistant text deltas into the placeholder message
        if let turn = newSnapshot.activeTurn {
            guard let turnID = turn.id else {
                print("[Stream] activeTurn.id is nil — can't match streaming session. text=\(turn.assistantText.prefix(80)) completed=\(turn.isCompleted)")
                return
            }
            // Anchor to the first active turn we see — don't rely on
            // runtime.latestTurnID which comes from a different event
            // (turn/start response) and may race with the snapshot update
            // from turn/started notification.
            if streamingTurnID == nil {
                streamingTurnID = turnID
                print("[Stream] anchored to turnID=\(turnID)")
            }
            guard streamingTurnID == turnID else {
                print("[Stream] turnID mismatch: expected \(streamingTurnID ?? "nil") got \(turnID)")
                return
            }

            let currentText = turn.assistantText
            if currentText.count > lastAssistantTextLength || turn.isCompleted {
                let newDelta = currentText.count > lastAssistantTextLength
                    ? String(currentText[currentText.index(currentText.startIndex, offsetBy: lastAssistantTextLength)...])
                    : ""
                lastAssistantTextLength = currentText.count
                // Log raw delta for debugging parser patterns
                if !newDelta.isEmpty {
                    print("[Stream] delta: \(newDelta.prefix(200))")
                }
                if let idx = messages.lastIndex(where: { $0.id == streamID }) {
                    let displayText = currentText.isEmpty ? "…" : currentText
                    print("[Stream] updating placeholder: count=\(currentText.count) completed=\(turn.isCompleted)")

                    // Parse streaming text for thinking / tool steps
                    let result = AssistantTextParser.extractNewSteps(from: currentText, previousLength: parsedTextLength)
                    parsedTextLength = result.scannedLength
                    let existingSteps = messages[idx].steps
                    let mergedSteps = mergeSteps(existingSteps, with: result.steps)

                    replaceMessage(at: idx, with: ConversationMessage(
                        id: streamID,
                        role: assistantName,
                        text: displayText,
                        steps: mergedSteps
                    ))
                }
            }

            // Turn completed — finalize and log to journal
            if turn.isCompleted {
                streamingMessageID = nil
                streamingTurnID = nil
                lastAssistantTextLength = 0
                parsedTextLength = 0
                journal.logAssistantMessage(assistantName, currentText)
            }
        }
    }

    private func replaceStreamingMessage(_ streamID: UUID, with message: String) {
        if let idx = messages.lastIndex(where: { $0.id == streamID }) {
            let existingSteps = messages[idx].steps
            replaceMessage(at: idx, with: ConversationMessage(id: streamID, role: "Tool", text: "Error: \(message)", steps: existingSteps))
        }
        streamingMessageID = nil
        streamingTurnID = nil
        lastAssistantTextLength = 0
        parsedTextLength = 0
    }

    /// Called when the runtime publishes updated steps.
    /// Merges lifecycle steps into the streaming message without touching its text.
    private func handleStepUpdate(_ steps: [TurnStep]) {
        guard let streamID = streamingMessageID,
              let idx = messages.lastIndex(where: { $0.id == streamID }) else {
            print("[Steps] handleStepUpdate skipped: streamingMessageID=\(streamingMessageID?.uuidString ?? "nil")")
            return
        }
        let existing = messages[idx]
        let merged = mergeSteps(existing.steps, with: steps)
        replaceMessage(at: idx, with: ConversationMessage(
            id: streamID,
            role: existing.role,
            text: existing.text,
            steps: merged
        ))
    }

    private func mergeSteps(_ existing: [TurnStep], with incoming: [TurnStep]) -> [TurnStep] {
        var merged = existing
        for step in incoming {
            if let index = merged.firstIndex(where: { $0.id == step.id }) {
                merged[index] = step
            } else {
                merged.append(step)
            }
        }
        return merged
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
        if isCreatingNewSession {
            switch event {
            case .notification(method: "error", params: _), .exit:
                rollbackNewSession()
            default:
                break
            }
        }
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
            // Use ingestWithRuntimeEvent to produce both StoredRelayEvents
            // and RuntimeEvents (for Trace/Timeline).
            let (events, newRuntimeEvents) = try relayService.ingestWithRuntimeEvent(
                event,
                runtime: currentRuntimeIdentifier,
                sessionID: activeRunID,
                runID: activeRunID
            )
            guard !events.isEmpty else { return }
            relaySnapshot = relayService.snapshotEnvelope().payload
            relayEventCount = relayService.eventCount
            relayStatusText = "relay seq=\(relaySnapshot.lastEventSeq) events=\(relayEventCount)"
            // Sync UI settings to relay service so broadcasts include model/effort/planMode
            syncSettingsToRelay()
            // Active push to all connected WebSocket clients
            broadcastGroupedSnapshot()
            // Update timeline when new RuntimeEvents arrive
            if !newRuntimeEvents.isEmpty {
                refreshTimeline()
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
        guard runtime.sessions.contains(where: { $0.sessionID == activeRunID }) else {
            // Archived sessions: save JSON directly
            let id = activeRunID
            if !id.isEmpty {
                journal.saveStructuredMessages(sessionID: id, messages: messages)
            }
            return
        }
        messageCache.save(messages: messages, for: activeRunID)
        // Also persist to disk for runtime sessions
        journal.saveStructuredMessages(sessionID: activeRunID, messages: messages)
    }

    private func bindCurrentMessages(toSession threadID: String) {
        if let archivedID = continuingArchivedSessionID {
            var saved = savedSessionIDs
            saved.remove(archivedID)
            saved.insert(threadID)
            savedSessionIDs = saved
            archivedSessionItems.removeAll(where: { $0.id == archivedID })
            activeRunID = threadID
            messageCache.save(messages: messages, for: threadID)
            continuingArchivedSessionID = nil
            return
        }
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

    private func restoreSavedRuntimeSessions(archivedIDs: Set<String>) {
        for id in savedSessionIDs where !archivedIDs.contains(id) && !runtime.sessions.contains(where: { $0.sessionID == id }) {
            runtime.rememberSession(
                sessionID: id,
                cwd: workspaceCWD,
                title: String(id.prefix(8)),
                status: "saved"
            )
        }
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

// MARK: - Agent Step Tracking

// TurnStepKind, StepStatus, TurnStep are defined in AgentClientCore (TurnStep.swift)
// and imported via the AgentClientMacShell module.

struct ConversationMessage: Identifiable, Codable {
    let id: UUID
    let role: String
    let text: String
    var steps: [TurnStep]

    init(role: String, text: String, steps: [TurnStep] = []) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.steps = steps
    }

    init(id: UUID, role: String, text: String, steps: [TurnStep] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.steps = steps
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

    mutating func cancelPendingNewSession() {
        pendingNewSession = nil
    }

    mutating func save(messages: [Message], for sessionID: String) {
        histories[sessionID] = messages
    }

    func messages(for sessionID: String) -> [Message] {
        histories[sessionID] ?? []
    }

    mutating func clear() {
        histories.removeAll()
        pendingNewSession = nil
    }
}

struct SessionTranscriptRestorer {
    static func restore<Message>(cached: [Message], archivedWithSteps: [Message], archivedPlain: [Message]) -> [Message] {
        if !cached.isEmpty { return cached }
        if !archivedWithSteps.isEmpty { return archivedWithSteps }
        return archivedPlain
    }
}

@MainActor
struct RuntimeLifecycleBinder {
    static func bind(
        runtime: AgentRuntime,
        onEvent: @escaping (CodexAppServerEvent) -> Void,
        onThreadStarted: @escaping (String) -> Void,
        onSessionStartFailed: @escaping (String) -> Void
    ) {
        runtime.onEventReceived = onEvent
        runtime.onThreadStarted = onThreadStarted
        runtime.onSessionStartFailed = onSessionStartFailed
    }
}

struct WorkspaceSessionGrouper {
    let workspaceCWD: String
    let savedSessionIDs: Set<String>
    let archivedSessionIDs: Set<String>
    let runtimeSessionCWDs: [String: String?]

    private var isWorkspaceGroupingActive: Bool {
        !savedSessionIDs.isEmpty || !archivedSessionIDs.isEmpty
    }

    func isWorkspaceSession(_ sessionID: String) -> Bool {
        if savedSessionIDs.contains(sessionID) || archivedSessionIDs.contains(sessionID) {
            return true
        }
        guard isWorkspaceGroupingActive,
              let cwd = runtimeSessionCWDs[sessionID] ?? nil
        else {
            return false
        }
        return Self.normalizedPath(cwd) == Self.normalizedPath(workspaceCWD)
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
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
