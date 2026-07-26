import Foundation

/// Builds the environment for PTY-spawned processes. Apps launched from
/// Finder get a bare PATH ("/usr/bin:/bin:…"), so we rebuild a sane one.
enum GCEnvironment {
    static func make(extra: [String: String] = [:]) -> [String] {
        var env = ProcessInfo.processInfo.environment

        let home = NSHomeDirectory()
        let preferred = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.claude/local",
        ]
        let etcPaths = (try? String(contentsOfFile: "/etc/paths", encoding: .utf8))?
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
        let inherited = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":")
            .map(String.init)

        var seen = Set<String>()
        let path = (preferred + inherited + etcPaths)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")

        env["PATH"] = path
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["GC_ACTIVE"] = "1"
        for (key, value) in extra {
            env[key] = value
        }
        return env.map { "\($0.key)=\($0.value)" }
    }
}

/// Finds the claude CLI binary on this machine.
enum ClaudeLocator {
    static func find() -> String? {
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(NSHomeDirectory())/.claude/local/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Last resort: ask the login shell's PATH.
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "which claude"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard let _ = try? process.run() else { return nil }
        process.waitUntilExit()
        let path = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0,
              !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }
}
