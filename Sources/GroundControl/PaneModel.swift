import AppKit
import Foundation
import GCCore
import SwiftTerm

/// One terminal pane: owns its SwiftTerm view and the claude process inside it.
/// The view is created once and reused so SwiftUI never spawns a second process.
@MainActor
final class PaneModel: ObservableObject, Identifiable {
    let id: UUID
    /// "T1", "T2"… — monotonic, never reused (like airport terminals).
    let label: String
    /// Forced via claude's --session-id so hook payloads map 1:1 to this pane.
    /// Regenerated on every (re)start so restarts get a fresh session.
    private(set) var sessionId: UUID

    @Published var cwd: String
    @Published var state: PaneState = .standby
    @Published var branch: String?
    /// Path to the session JSONL transcript — set on first UserPromptSubmit.
    @Published var transcriptPath: String?
    /// Cumulative token usage + model for this session, refreshed after each Stop.
    @Published var sessionUsage: SessionUsage?

    private let server: ServerConfig
    /// If set, claude is launched with --resume so the conversation continues.
    /// Cleared after first use so a manual restart starts fresh.
    private var resumeSessionId: String?
    /// If set, claude is launched with --resume <id> --fork-session to branch
    /// from a parent session, giving the sub-agent full context of the parent.
    private var forkFromSessionId: String?
    /// True when this pane was created as a fork (sub-agent). Forks never
    /// claim the project's lastSessionId slot — the parent's session should
    /// be what resumes next time the user opens that folder.
    let isFork: Bool
    /// If set, sent as the first prompt once the session starts.
    var pendingTask: String?
    /// Called on MainActor when the process exits — AppState uses this to land active flights.
    var onTerminated: (() -> Void)?
    private var terminalView: LocalProcessTerminalView?
    private var claudePath: String?

    init(label: String, cwd: String, server: ServerConfig,
         resumeSessionId: String? = nil, forkFromSessionId: String? = nil) {
        self.id = UUID()
        self.sessionId = UUID()
        self.label = label
        self.cwd = cwd
        self.server = server
        self.resumeSessionId = resumeSessionId
        self.forkFromSessionId = forkFromSessionId
        self.isFork = forkFromSessionId != nil
        self.claudePath = ClaudeLocator.find()
    }

    /// Called by the NSViewRepresentable; starts the process on first use.
    func ensureStarted() -> LocalProcessTerminalView {
        if let view = terminalView { return view }
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        view.processDelegate = self
        view.nativeBackgroundColor = .gcPanel
        view.nativeForegroundColor = .gcText
        view.caretColor = .gcRadar
        view.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        terminalView = view
        start(view)
        return view
    }

    private func start(_ view: LocalProcessTerminalView) {
        guard let claude = claudePath else {
            view.feed(text: "GROUND CONTROL: claude CLI not found on PATH.\r\n")
            view.startProcess(
                executable: "/bin/zsh",
                args: ["-l"],
                environment: GCEnvironment.make(),
                currentDirectory: cwd
            )
            state = .noContact
            return
        }

        // Three launch modes:
        // 1. Fork from parent: --resume <parentId> --fork-session --session-id <newUUID>
        //    Sub-agent inherits full conversation history of the parent session.
        // 2. Resume: --resume <existingId> only (CLI rejects combining with --session-id)
        //    Hooks arrive with the original UUID, so we adopt it for routing.
        // 3. New session: --session-id <newUUID> for fresh 1:1 hook routing.
        var args: [String]
        if let forkId = forkFromSessionId {
            sessionId = UUID()
            args = ["--resume", forkId, "--fork-session", "--session-id", sessionId.uuidString]
            forkFromSessionId = nil
        } else if let resumeId = resumeSessionId, let existingUUID = UUID(uuidString: resumeId) {
            sessionId = existingUUID   // hooks arrive with this UUID — keep them routing here
            args = ["--resume", resumeId]
            resumeSessionId = nil      // only on first start; manual restart begins fresh
        } else {
            sessionId = UUID()
            args = ["--session-id", sessionId.uuidString]
        }

        do {
            let settingsPath = try SessionConfigWriter.writeSettings(sessionId: sessionId, server: server)
            args += ["--settings", settingsPath]
            if let mcpPath = try SessionConfigWriter.writeMCPConfig(sessionId: sessionId, pane: label, server: server) {
                args += ["--mcp-config", mcpPath]
            }
        } catch {
            print("[pane \(label)] failed to write session config: \(error)")
        }

        view.startProcess(
            executable: claude,
            args: args,
            environment: GCEnvironment.make(extra: [
                "GC_SESSION_ID": sessionId.uuidString,
                "GC_PANE": label,
            ]),
            currentDirectory: cwd
        )
        state = .standby
    }

    /// Type text into the terminal as if the user typed it (writes to stdin).
    func sendInput(_ text: String) {
        terminalView?.send(txt: text)
    }

    /// Export the session transcript as markdown to the Desktop and open it.
    func exportSession() {
        guard let path = transcriptPath else { return }
        let markdown = TranscriptReader.exportMarkdown(path: path, label: label)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())
        let dest = NSHomeDirectory() + "/Desktop/\(label)-session-\(date).md"
        try? markdown.write(toFile: dest, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(URL(fileURLWithPath: dest))
    }

    /// Refresh token usage + model from the transcript on a background thread.
    func refreshUsage() {
        guard let path = transcriptPath else { return }
        Task { [weak self] in
            let usage = await Task.detached(priority: .utility) {
                TranscriptReader.readUsage(path: path)
            }.value
            self?.sessionUsage = usage
        }
    }

    /// Kill and relaunch the process in the same view.
    func restart() {
        guard let view = terminalView else { return }
        view.terminate()
        // Give the old process a beat to die before reusing the PTY.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak view] in
            guard let self, let view else { return }
            view.getTerminal().resetToInitialState()
            view.setNeedsDisplay(view.bounds)
            self.start(view)
        }
    }

    func terminate() {
        terminalView?.terminate()
    }

    /// Refresh the git branch shown in the title bar (called on a timer).
    func refreshGit() {
        let directory = cwd
        Task {
            // Outer task stays on MainActor; only the git shell-out leaves it.
            let info = await Task.detached(priority: .utility) {
                GitStatus.info(cwd: directory)
            }.value
            if let info {
                branch = info.dirty > 0 ? "\(info.branch) ±\(info.dirty)" : info.branch
            } else {
                branch = nil
            }
        }
    }
}

// MARK: - SwiftTerm delegate (called on SwiftTerm's queue — hop to MainActor)

extension PaneModel: LocalProcessTerminalViewDelegate {
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            guard self.state != .standby else { return }
            self.state = (exitCode ?? 0) == 0 ? .dark : .noContact
            self.onTerminated?()
        }
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        Task { @MainActor in
            guard let directory, let url = URL(string: directory) else { return }
            self.cwd = url.path
        }
    }
}
