import Foundation
import GCCore

/// Writes the per-session claude settings file that wires http hooks back to us.
/// Files live in $TMPDIR/groundcontrol/ and never touch the user's project.
enum SessionConfigWriter {
    static func writeSettings(sessionId: UUID, server: ServerConfig) throws -> String {
        let hook: [String: Any] = [
            "type": "http",
            "url": "http://127.0.0.1:\(server.port)/hook",
            "headers": ["Authorization": "Bearer \(server.token)"],
            "timeout": 5,
        ]
        let events = [
            "SessionStart",
            "UserPromptSubmit",
            "PermissionRequest",
            "Notification",
            "Stop",
            "SessionEnd",
        ]
        var hooks: [String: Any] = [:]
        for event in events {
            hooks[event] = [["hooks": [hook]]]
        }
        let settings: [String: Any] = ["hooks": hooks]

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        let file = try configFile(named: "settings-\(sessionId.uuidString).json")
        try data.write(to: file)
        return file.path
    }

    /// Writes the per-session MCP config pointing claude at the bundled gc-mcp,
    /// with the server address/token/pane identity baked into its environment.
    /// Returns nil when no gc-mcp binary can be found (e.g. unbundled run).
    static func writeMCPConfig(sessionId: UUID, pane: String, server: ServerConfig) throws -> String? {
        guard let binary = gcMCPBinaryPath() else { return nil }
        let config: [String: Any] = [
            "mcpServers": [
                "groundcontrol": [
                    "command": binary,
                    "env": [
                        "GC_SERVER": "http://127.0.0.1:\(server.port)",
                        "GC_TOKEN": server.token,
                        "GC_SESSION_ID": sessionId.uuidString,
                        "GC_PANE": pane,
                    ],
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        let file = try configFile(named: "mcp-\(sessionId.uuidString).json")
        try data.write(to: file)
        return file.path
    }

    /// gc-mcp lives next to the app binary: in the bundle when bundled,
    /// in the swift build products dir when run via `swift run`.
    static func gcMCPBinaryPath() -> String? {
        if let executable = Bundle.main.executableURL {
            let beside = executable.deletingLastPathComponent()
                .appendingPathComponent("gc-mcp").path
            if FileManager.default.isExecutableFile(atPath: beside) {
                return beside
            }
        }
        return nil
    }

    private static func configFile(named name: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("groundcontrol", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }
}
