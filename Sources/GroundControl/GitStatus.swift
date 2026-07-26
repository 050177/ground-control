import Foundation

/// Lightweight git info for pane title bars. Shells out — no libgit2.
enum GitStatus {
    /// Branch name and number of dirty files, or nil outside a repo.
    /// Safe to call off the main thread.
    static func info(cwd: String) -> (branch: String, dirty: Int)? {
        guard let branch = run(["/usr/bin/git", "-C", cwd, "symbolic-ref", "--short", "HEAD"])
                ?? run(["/usr/bin/git", "-C", cwd, "rev-parse", "--short", "HEAD"]),
              !branch.isEmpty else {
            return nil
        }
        let dirtyFiles = run(["/usr/bin/git", "-C", cwd, "status", "--porcelain"])?
            .split(separator: "\n")
            .count ?? 0
        return (branch, dirtyFiles)
    }

    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard let _ = try? process.run() else { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
