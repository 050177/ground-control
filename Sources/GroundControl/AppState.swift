import AppKit
import Foundation
import GCCore

struct ChatterLine: Identifiable {
    let id = UUID()
    let text: String
}

/// Root app state: terminal panes, selection, the board, the chatter ticker.
@MainActor
final class AppState: ObservableObject {
    @Published var panes: [PaneModel] = []
    @Published var selectedPaneId: UUID?
    @Published var board: Board
    @Published var boardVisible = true
    @Published var tutorialVisible = false
    @Published var chatter: [ChatterLine] = []
    /// Non-nil when a newer GitHub release is available.
    @Published var pendingUpdate: UpdateInfo?
    /// Paths of panes that were open last time the app ran — shown as "restore" prompt.
    @Published var savedSessionPaths: [String] = []

    let boardStore: BoardStore
    let recentProjects: RecentProjectsStore
    private let hookServer: HookServer

    /// Last directory chosen — new terminals open next to the previous one.
    private var lastDirectory: String = NSHomeDirectory()

    /// Lowest T-number not currently in use, so closed slots are reclaimed:
    /// close T1, reopen same folder → T1 again rather than T3.
    private var nextAvailableNumber: Int {
        let used = Set(panes.compactMap { Int($0.label.dropFirst()) })
        var n = 1
        while used.contains(n) { n += 1 }
        return n
    }

    private static var lastSessionURL: URL {
        ServerConfig.appSupportDirectory.appendingPathComponent("last-session.json")
    }

    init() {
        let store = BoardStore()
        boardStore = store
        board = store.board
        recentProjects = RecentProjectsStore()
        hookServer = HookServer(board: store)
        hookServer.onHook = { [weak self] event in self?.handleHook(event) }
        hookServer.onBoardChanged = { [weak self] newBoard in self?.board = newBoard }
        do {
            try hookServer.start()
        } catch {
            appendChatter("GC · hook server failed to start — no status radar")
        }
        Notify.requestAuthorization()
        startGitPolling()
        loadSavedSession()
        Task { await checkForUpdate() }
    }

    // MARK: - Terminals

    /// Prompt for a project directory, then add a terminal there.
    func addTerminalPrompt() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Project"
        panel.message = "Choose a project directory for this terminal"
        panel.directoryURL = URL(fileURLWithPath: lastDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addTerminal(directory: url.path)
    }

    @discardableResult
    func addTerminal(directory: String, resumeSessionId: String? = nil,
                     fresh: Bool = false, forkFromSessionId: String? = nil) -> PaneModel? {
        guard let server = hookServer.config else {
            appendChatter("GC · hook server not ready — try again in a moment")
            return nil
        }
        // Record open; fresh=true skips resume (e.g. split pane — independent new session).
        let knownSession = recentProjects.didOpen(path: directory)
        let sessionToResume = fresh ? nil : (resumeSessionId ?? knownSession)

        let pane = PaneModel(
            label: "T\(nextAvailableNumber)",
            cwd: directory,
            server: server,
            resumeSessionId: sessionToResume,
            forkFromSessionId: forkFromSessionId
        )
        lastDirectory = directory
        panes.append(pane)
        selectedPaneId = pane.id
        if let sid = sessionToResume {
            appendChatter("\(pane.label) · resuming session \(String(sid.prefix(8)))…")
        } else {
            appendChatter("\(pane.label) · terminal open — \(abbreviate(directory))")
        }
        return pane
    }

    /// Open a recent project — passes its stored session ID for resume automatically.
    func openRecent(_ project: RecentProject) {
        addTerminal(directory: project.path, resumeSessionId: project.lastSessionId)
    }

    /// Fork a pane — new session in the same directory branched from the parent's
    /// conversation history so the sub-agent has full context of what T2 was doing.
    func splitPane(_ pane: PaneModel, task: String = "") {
        let parentSessionId = pane.sessionId.uuidString
        guard let newPane = addTerminal(
            directory: pane.cwd,
            fresh: true,
            forkFromSessionId: parentSessionId
        ) else { return }
        if !task.isEmpty {
            newPane.pendingTask = task
        }
    }

    func removeTerminal(_ id: UUID) {
        guard let index = panes.firstIndex(where: { $0.id == id }) else { return }
        let pane = panes[index]
        pane.terminate()
        panes.remove(at: index)
        appendChatter("\(pane.label) · terminal closed")
        if selectedPaneId == id {
            selectedPaneId = panes.last?.id
        }
    }

    func shutdown() {
        saveLastSession()
        for pane in panes {
            pane.terminate()
        }
        hookServer.stop()
    }

    // MARK: - Session restore

    private func loadSavedSession() {
        guard let data = try? Data(contentsOf: Self.lastSessionURL),
              let paths = try? JSONDecoder().decode([String].self, from: data),
              !paths.isEmpty else { return }
        savedSessionPaths = paths
    }

    func openLastSession() {
        let paths = savedSessionPaths
        savedSessionPaths = []
        try? FileManager.default.removeItem(at: Self.lastSessionURL)
        for path in paths {
            addTerminal(directory: path)
        }
    }

    func dismissSavedSession() {
        savedSessionPaths = []
        try? FileManager.default.removeItem(at: Self.lastSessionURL)
    }

    private func saveLastSession() {
        // Exclude forks — sub-agents are ephemeral and shouldn't restore alongside
        // the parent; the parent's session is what the user wants to return to.
        let paths = panes.filter { !$0.isFork }.map { $0.cwd }
        guard !paths.isEmpty,
              let data = try? JSONEncoder().encode(paths) else { return }
        try? data.write(to: Self.lastSessionURL, options: .atomic)
    }

    // MARK: - Update check

    private func checkForUpdate() async {
        guard let update = await UpdateChecker.check() else { return }
        pendingUpdate = update
        appendChatter("GC · update available — \(update.version)")
    }

    // MARK: - Board

    func toggleBoard() {
        boardVisible.toggle()
    }

    func showTutorial() {
        tutorialVisible = true
    }

    /// File a flight plan from the board's input row (same process — no HTTP hop).
    func removeFlight(id: UUID) {
        boardStore.update { board in
            board.flights.removeAll { $0.id == id }
        }
        board = boardStore.board
    }

    /// Auto-file or update the active flight for a pane from a UserPromptSubmit message.
    private func autoFileFlight(pane: PaneModel, message: String?) {
        let title: String
        if let msg = message?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
            // Truncate long prompts to a readable label.
            title = msg.count > 72 ? String(msg.prefix(69)) + "…" : msg
        } else {
            title = "Working…"
        }

        // If the pane already has an active (non-terminal) flight, update it.
        // Otherwise create a new one.
        var number = 0
        boardStore.update { board in
            if let idx = board.flights.firstIndex(where: {
                $0.assignedPane == pane.label &&
                $0.status != .landed && $0.status != .cancelled
            }) {
                board.flights[idx].title = title
                board.flights[idx].status = .departed
                board.flights[idx].sessionId = pane.sessionId.uuidString
                board.flights[idx].updatedAt = Date()
                number = board.flights[idx].number
            } else {
                number = board.nextFlightNumber
                board.flights.append(Flight(
                    number: number,
                    title: title,
                    status: .departed,
                    assignedPane: pane.label,
                    sessionId: pane.sessionId.uuidString,
                    projectPath: pane.cwd
                ))
                board.nextFlightNumber += 1
            }
        }
        board = boardStore.board
        appendChatter("\(pane.label) · #\(String(format: "%02d", number)) DEPARTED — \(title.prefix(40))")
    }

    /// Land the active flight for a pane when the agent finishes its turn.
    private func landActiveFlight(pane: PaneModel) {
        boardStore.update { board in
            for idx in board.flights.indices {
                if board.flights[idx].assignedPane == pane.label &&
                   (board.flights[idx].status == .departed || board.flights[idx].status == .holding) {
                    board.flights[idx].status = .landed
                    board.flights[idx].updatedAt = Date()
                }
            }
        }
        board = boardStore.board
    }

    private func resumeActiveFlight(pane: PaneModel) {
        boardStore.update { board in
            for idx in board.flights.indices {
                if board.flights[idx].assignedPane == pane.label &&
                   board.flights[idx].status == .holding {
                    board.flights[idx].status = .departed
                    board.flights[idx].updatedAt = Date()
                }
            }
        }
        board = boardStore.board
    }

    private func updateFlightActivity(pane: PaneModel, activity: String) {
        boardStore.update { board in
            for idx in board.flights.indices where board.flights[idx].assignedPane == pane.label
                && board.flights[idx].status == .departed {
                board.flights[idx].notes = activity
                board.flights[idx].updatedAt = Date()
            }
        }
        board = boardStore.board
    }

    private func clearFlightActivity(pane: PaneModel) {
        boardStore.update { board in
            for idx in board.flights.indices where board.flights[idx].assignedPane == pane.label {
                board.flights[idx].notes = ""
            }
        }
        board = boardStore.board
    }

    private func holdActiveFlight(pane: PaneModel) {
        boardStore.update { board in
            for idx in board.flights.indices {
                if board.flights[idx].assignedPane == pane.label &&
                   board.flights[idx].status == .departed {
                    board.flights[idx].status = .holding
                    board.flights[idx].updatedAt = Date()
                }
            }
        }
        board = boardStore.board
    }

    func focusPane(label: String) {
        guard let pane = panes.first(where: { $0.label == label }) else { return }
        selectedPaneId = pane.id
        appendChatter("\(label) · on frequency")
    }

    /// Focus the pane for a flight, or reopen a terminal if it was closed.
    func focusOrReopenFlight(_ flight: Flight) {
        if let label = flight.assignedPane,
           let pane = panes.first(where: { $0.label == label }) {
            selectedPaneId = pane.id
            appendChatter("\(label) · on frequency")
        } else if let path = flight.projectPath {
            addTerminal(directory: path, resumeSessionId: flight.sessionId)
        }
    }

    // MARK: - Chatter

    func appendChatter(_ text: String) {
        chatter.append(ChatterLine(text: text))
        if chatter.count > 100 {
            chatter.removeFirst(chatter.count - 100)
        }
    }

    // MARK: - Private


    private func startGitPolling() {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.panes.forEach { $0.refreshGit() }
            }
        }.fire()
    }

    private func handleHook(_ event: HookEvent) {
        guard let pane = panes.first(where: {
            $0.sessionId.uuidString.lowercased() == event.sessionId.lowercased()
        }) else {
            return
        }
        switch event.event {
        case "SessionStart":
            pane.state = .standby
            // Forks are sub-agents — don't overwrite the project's main session ID.
            if !pane.isFork {
                recentProjects.didStartSession(path: pane.cwd, sessionId: event.sessionId)
            }
            appendChatter("\(pane.label) · session on the tarmac")
            if let task = pane.pendingTask, !task.isEmpty {
                pane.pendingTask = nil
                // Delay to let claude render its welcome screen before we send input.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak pane] in
                    pane?.sendInput(task + "\n")
                }
            }
        case "UserPromptSubmit":
            pane.state = .departed
            clearFlightActivity(pane: pane)
            autoFileFlight(pane: pane, message: event.message)
            // transcript_path filename is the definitive resume UUID — use it if present.
            // Skip for forks so sub-agents don't overwrite the parent project's session slot.
            if !pane.isFork, let tp = event.transcriptPath {
                let resumeId = URL(fileURLWithPath: tp).deletingPathExtension().lastPathComponent
                if !resumeId.isEmpty {
                    recentProjects.didStartSession(path: pane.cwd, sessionId: resumeId)
                }
            }
        case "PreToolUse":
            // A tool is about to run — permission was already granted (or auto-accepted).
            // Flip back to DEPARTED so the pane doesn't stay stuck on HOLDING.
            if pane.state == .holding {
                pane.state = .departed
                resumeActiveFlight(pane: pane)
            }
            // Update the board row with what the agent is doing right now.
            if let activity = event.toolActivity {
                updateFlightActivity(pane: pane, activity: activity)
            }
        case "PermissionRequest":
            pane.state = .holding
            holdActiveFlight(pane: pane)
            appendChatter("\(pane.label) · HOLDING — awaiting clearance")
            Notify.post(title: "\(pane.label) is holding", body: "Agent needs clearance to continue.")
        case "Notification":
            // Informational only — Claude fires these for progress updates, "accept edits on",
            // extended thinking status, etc. Does NOT mean the agent is waiting for user input.
            appendChatter("\(pane.label) · notification")
        case "Stop":
            pane.state = .landed
            clearFlightActivity(pane: pane)
            landActiveFlight(pane: pane)
            appendChatter("\(pane.label) · LANDED")
            Notify.post(title: "\(pane.label) landed", body: "Agent finished its turn.")
        case "SessionEnd":
            pane.state = .dark
            appendChatter("\(pane.label) · DARK — session ended")
        default:
            break
        }
    }

    private func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
