import Foundation
import GCCore
import MCP

// MARK: - Configuration
// Injected by the app's generated --mcp-config env block; server.json is the fallback.

struct Config {
    let baseURL: String
    let token: String
    let sessionId: String
    let pane: String

    static func load() -> Config? {
        let env = ProcessInfo.processInfo.environment
        var base = env["GC_SERVER"]
        var token = env["GC_TOKEN"]
        if base == nil || token == nil, let cfg = ServerConfig.existing() {
            base = base ?? "http://127.0.0.1:\(cfg.port)"
            token = token ?? cfg.token
        }
        guard let base, let token else { return nil }
        return Config(
            baseURL: base,
            token: token,
            sessionId: env["GC_SESSION_ID"] ?? "",
            pane: env["GC_PANE"] ?? ""
        )
    }
}

// MARK: - HTTP client for the app's API

final class APIClient: @unchecked Sendable {
    let config: Config

    init(config: Config) {
        self.config = config
    }

    /// Returns (statusCode, response body as text).
    func call(_ method: String, _ path: String, json: [String: Any]? = nil) async throws -> (Int, String) {
        var request = URLRequest(url: URL(string: config.baseURL + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data, as: UTF8.self))
    }
}

// MARK: - Entry point

guard let config = Config.load() else {
    FileHandle.standardError.write(
        "gc-mcp: Ground Control app is not running (no server config)\n".data(using: .utf8)!
    )
    exit(1)
}
let api = APIClient(config: config)

let server = Server(
    name: "groundcontrol",
    version: "0.1.0",
    capabilities: .init(tools: .init())
)
let transport = StdioTransport()
try await server.start(transport: transport)

@Sendable func schema(_ properties: [String: Value], required: [String] = []) -> Value {
    .object([
        "type": "object",
        "properties": .object(properties),
        "required": .array(required.map { .string($0) }),
    ])
}

@Sendable func field(_ description: String, _ type: String = "string") -> Value {
    .object(["type": .string(type), "description": .string(description)])
}

let statuses = "scheduled|boarding|departed|holding|landed|cancelled"

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: [
        Tool(
            name: "departures_list",
            description: "List all flights (tasks) on the Ground Control departures board with their status and assigned terminal.",
            inputSchema: schema([:])
        ),
        Tool(
            name: "departures_file",
            description: "File a flight plan: create a new task on the Ground Control departures board.",
            inputSchema: schema([
                "title": field("Short task title, e.g. 'Fix login redirect'"),
                "notes": field("Optional details or acceptance criteria"),
            ], required: ["title"])
        ),
        Tool(
            name: "departures_update",
            description: "Update a flight's status (\(statuses)), title, or notes.",
            inputSchema: schema([
                "flight": field("Flight number (e.g. \"7\") or id"),
                "status": field(statuses),
                "title": field("New title"),
                "notes": field("New notes"),
            ], required: ["flight"])
        ),
        Tool(
            name: "departures_claim",
            description: "Claim a flight for this terminal: assigns it to your pane and marks it boarding.",
            inputSchema: schema([
                "flight": field("Flight number (e.g. \"7\") or id"),
            ], required: ["flight"])
        ),
        Tool(
            name: "departures_get",
            description: "Get a single flight by number or id.",
            inputSchema: schema([
                "flight": field("Flight number (e.g. \"7\") or id"),
            ], required: ["flight"])
        ),
        Tool(
            name: "preview_url",
            description: "Set the Ground Control preview panel to display a URL. Call this when you start a local dev server or write an HTML file — the preview panel opens automatically and navigates there.",
            inputSchema: schema([
                "url": field("URL to display, e.g. http://localhost:5173 or file:///path/to/index.html"),
            ], required: ["url"])
        ),
    ])
}

await server.withMethodHandler(CallTool.self) { params in
    func result(_ text: String, _ isError: Bool = false) -> CallTool.Result {
        .init(content: [.text(text)], isError: isError)
    }

    do {
        switch params.name {
        case "departures_list":
            let (status, body) = try await api.call("GET", "/api/flights")
            return result(body, status != 200)

        case "departures_file":
            guard let title = params.arguments?["title"]?.stringValue,
                  !title.isEmpty else {
                return result("title is required", true)
            }
            var json: [String: Any] = [
                "title": title,
                "sessionId": config.sessionId,
                "projectPath": FileManager.default.currentDirectoryPath,
            ]
            if let notes = params.arguments?["notes"]?.stringValue {
                json["notes"] = notes
            }
            let (status, body) = try await api.call("POST", "/api/flights", json: json)
            return result(body, status != 201)

        case "departures_update":
            guard let flight = params.arguments?["flight"]?.stringValue else {
                return result("flight is required", true)
            }
            var json: [String: Any] = [:]
            if let status = params.arguments?["status"]?.stringValue { json["status"] = status }
            if let title = params.arguments?["title"]?.stringValue { json["title"] = title }
            if let notes = params.arguments?["notes"]?.stringValue { json["notes"] = notes }
            guard !json.isEmpty else {
                return result("nothing to update", true)
            }
            let (status, body) = try await api.call("PATCH", "/api/flights/\(flight)", json: json)
            return result(body, status != 200)

        case "departures_claim":
            guard let flight = params.arguments?["flight"]?.stringValue else {
                return result("flight is required", true)
            }
            let (status, body) = try await api.call("PATCH", "/api/flights/\(flight)", json: [
                "status": "boarding",
                "assignedPane": config.pane,
                "sessionId": config.sessionId,
            ])
            return result(body, status != 200)

        case "departures_get":
            guard let flight = params.arguments?["flight"]?.stringValue else {
                return result("flight is required", true)
            }
            let (status, body) = try await api.call("GET", "/api/flights/\(flight)")
            return result(body, status != 200)

        case "preview_url":
            guard let url = params.arguments?["url"]?.stringValue, !url.isEmpty else {
                return result("url is required", true)
            }
            let (status, body) = try await api.call("POST", "/api/preview", json: ["url": url])
            return result(body, status != 200)

        default:
            return result("unknown tool: \(params.name)", true)
        }
    } catch {
        return result("ground control unreachable: \(error.localizedDescription)", true)
    }
}

// The server runs until claude ends the session and kills this process.
// (Park in bounded chunks: converting huge Durations to nanoseconds overflows.)
while true {
    try await Task.sleep(for: .seconds(3600))
}
