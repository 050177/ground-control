import Foundation

/// Discovers the running app's localhost server (port + bearer token).
/// Written by the app, read by gc-mcp. Lives in
/// ~/Library/Application Support/GroundControl/server.json
public struct ServerConfig: Codable, Sendable {
    public var port: Int
    public var token: String

    public init(port: Int, token: String) {
        self.port = port
        self.token = token
    }

    public static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("GroundControl", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var fileURL: URL {
        appSupportDirectory.appendingPathComponent("server.json")
    }

    public static func existing() -> ServerConfig? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ServerConfig.self, from: data)
    }

    /// Called by the app at startup. Reuses the existing token so sessions
    /// launched before a restart can still authenticate; only the port changes.
    @discardableResult
    public static func publish(port: Int) -> ServerConfig {
        let token = existing()?.token ?? UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let config = ServerConfig(port: port, token: token)
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return config
    }
}
