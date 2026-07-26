import Foundation

public struct RecentProject: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var path: String
    /// The claude session ID from the last run in this directory.
    /// Passed to `--resume` so the conversation picks up where it left off.
    public var lastSessionId: String?
    public var lastOpenedAt: Date
    public var openCount: Int

    public var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    public var abbreviatedPath: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    public init(path: String) {
        self.id = UUID()
        self.path = path
        self.lastSessionId = nil
        self.lastOpenedAt = Date()
        self.openCount = 1
    }
}

/// Persists the list of recently opened project directories with their last
/// session IDs so Ground Control can offer one-click resume.
public final class RecentProjectsStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    public private(set) var projects: [RecentProject]

    public static let maxCount = 12

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ServerConfig.appSupportDirectory
            .appendingPathComponent("recent-projects.json")
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? Self.decoder.decode([RecentProject].self, from: data) {
            projects = decoded
        } else {
            projects = []
        }
    }

    /// Record an open. Updates lastOpenedAt, bumps count, surfaces to top.
    /// Returns the existing lastSessionId so the caller can decide whether to resume.
    @discardableResult
    public func didOpen(path: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let index = projects.firstIndex(where: { $0.path == path }) {
            projects[index].lastOpenedAt = Date()
            projects[index].openCount += 1
            let sid = projects[index].lastSessionId
            // bubble to front
            let project = projects.remove(at: index)
            projects.insert(project, at: 0)
            persist()
            return sid
        } else {
            var project = RecentProject(path: path)
            projects.insert(project, at: 0)
            if projects.count > Self.maxCount {
                projects = Array(projects.prefix(Self.maxCount))
            }
            persist()
            return nil
        }
    }

    /// Called when a new claude session starts in a directory — save its ID
    /// so we can offer --resume next time.
    public func didStartSession(path: String, sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let index = projects.firstIndex(where: { $0.path == path }) else { return }
        projects[index].lastSessionId = sessionId
        persist()
    }

    public func remove(path: String) {
        lock.lock()
        defer { lock.unlock() }
        projects.removeAll { $0.path == path }
        persist()
    }

    private func persist() {
        guard let data = try? Self.encoder.encode(projects) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}
