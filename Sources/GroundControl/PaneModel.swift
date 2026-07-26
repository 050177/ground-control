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

    private let server: ServerConfig
    /// If set, claude is launched with --resume so the conversation continues.
    /// Cleared after first use so a manual restart starts fresh.
    private var resumeSessionId: String?
    private var terminalView: LocalProcessTerminalView?
    private var claudePath: String?

    init(label: String, cwd: String, server: ServerConfig, resumeSessionId: String? = nil) {
        self.id = UUID()
        self.sessionId = UUID()
        self.label = label
        self.cwd = cwd
        self.server = server
        self.resumeSessionId = resumeSessionId
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
        // When resuming, reuse the stored session UUID as --session-id too.
        // Passing a *new* --session-id alongside --resume causes claude to start
        // a fresh session (the two IDs conflict). Same value = unambiguous resume.
        if let resumeId = resumeSessionId, let existingUUID = UUID(uuidString: resumeId) {
            sessionId = existingUUID
        } else {
            sessionId = UUID()
        }

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

        var args = ["--session-id", sessionId.uuidString]

        if resumeSessionId != nil {
            args += ["--resume", sessionId.uuidString]
            resumeSessionId = nil  // only on first start; manual restart begins fresh
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
            // A restart kills the old process; don't clobber the fresh state.
            guard self.state != .standby else { return }
            self.state = (exitCode ?? 0) == 0 ? .dark : .noContact
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
