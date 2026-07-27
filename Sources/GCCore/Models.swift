import Foundation

/// A task on the departures board. Agents file flights; terminals fly them.
public struct Flight: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Human-facing flight number, monotonic (#07, #12…)
    public var number: Int
    public var title: String
    public var notes: String
    public var status: FlightStatus
    /// Pane label this flight is assigned to ("T1"), if any.
    public var assignedPane: String?
    /// Claude session id working this flight, if any.
    public var sessionId: String?
    public var projectPath: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        number: Int,
        title: String,
        notes: String = "",
        status: FlightStatus = .scheduled,
        assignedPane: String? = nil,
        sessionId: String? = nil,
        projectPath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.notes = notes
        self.status = status
        self.assignedPane = assignedPane
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum FlightStatus: String, Codable, CaseIterable, Sendable {
    case scheduled, boarding, departed, holding, landed, cancelled

    public var label: String { rawValue.uppercased() }
}

/// Live state of a terminal pane.
public enum PaneState: String, Codable, Sendable {
    /// Idle at the claude prompt, nothing in flight.
    case standby
    /// Agent is working (UserPromptSubmit seen).
    case departed
    /// Agent needs input (PermissionRequest / Notification).
    case holding
    /// Agent finished its turn (Stop seen).
    case landed
    /// Process exited normally.
    case dark
    /// Process died unexpectedly.
    case noContact

    public var label: String {
        switch self {
        case .standby: return "STANDBY"
        case .departed: return "DEPARTED"
        case .holding: return "HOLDING"
        case .landed: return "LANDED"
        case .dark: return "DARK"
        case .noContact: return "NO CONTACT"
        }
    }
}

/// Payload posted by claude http hooks. Unknown fields are ignored;
/// every field is tolerated as missing so a claude update can't break us.
public struct HookEvent: Codable, Sendable {
    public let sessionId: String
    public let event: String
    public let cwd: String?
    public let permissionMode: String?
    /// The user's prompt text — present on UserPromptSubmit only.
    /// Actual field name is "prompt" in claude 2.x.
    public let message: String?
    /// Path to the session JSONL file. The filename (without extension) is the
    /// UUID needed for `--resume`. Present on UserPromptSubmit.
    public let transcriptPath: String?
    /// Present on PreToolUse — the tool being invoked (e.g. "Read", "Bash").
    public let toolName: String?
    /// Short human-readable label derived from toolName + tool_input,
    /// e.g. "Reading · src/auth.ts" or "Bash · npm test". nil if not a tool event.
    public let toolActivity: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        sessionId      = c.decode("session_id") ?? ""
        event          = c.decode("hook_event_name") ?? ""
        cwd            = c.decode("cwd")
        permissionMode = c.decode("permission_mode")
        transcriptPath = c.decode("transcript_path")
        message = c.decode("prompt") ?? c.decode("message") ?? c.decode("user_message") ?? c.decode("input")
        let tName = c.decode("tool_name")
        toolName = tName
        // Build a readable activity string from tool_name + tool_input fields.
        if let tName {
            let input = (try? c.nestedContainer(keyedBy: DynamicKey.self,
                                                forKey: DynamicKey(stringValue: "tool_input")))
            let path    = input?.decode("file_path") ?? input?.decode("path")
            let command = input?.decode("command")
            let url     = input?.decode("url")
            let query   = input?.decode("query")
            toolActivity = HookEvent.activityLabel(tool: tName,
                                                   param: path ?? command ?? url ?? query)
        } else {
            toolActivity = nil
        }
    }

    public init(sessionId: String, event: String, cwd: String? = nil,
                permissionMode: String? = nil, message: String? = nil,
                transcriptPath: String? = nil, toolName: String? = nil,
                toolActivity: String? = nil) {
        self.sessionId      = sessionId
        self.event          = event
        self.cwd            = cwd
        self.permissionMode = permissionMode
        self.message        = message
        self.transcriptPath = transcriptPath
        self.toolName       = toolName
        self.toolActivity   = toolActivity
    }

    private static func activityLabel(tool: String, param: String?) -> String {
        let verb: String
        switch tool.lowercased() {
        case "read", "view":              verb = "Reading"
        case "edit", "multiedit":         verb = "Editing"
        case "write":                     verb = "Writing"
        case "bash":                      verb = "Bash"
        case "ls", "glob":               verb = "Browsing"
        case "grep":                      verb = "Searching"
        case "webfetch":                  verb = "Fetching"
        case "websearch":                 verb = "Searching web"
        case "todoread", "todowrite":     verb = "Tasks"
        case "agent":                     verb = "Sub-agent"
        default:
            // mcp__ prefixed tools — strip prefix and title-case
            if tool.hasPrefix("mcp__") {
                verb = tool.dropFirst(5).split(separator: "_")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                    .joined(separator: " ")
            } else {
                verb = tool
            }
        }
        guard let p = param?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else {
            return verb
        }
        // Trim long params — keep last path component for file paths, first 40 chars for commands.
        let short: String
        if tool.lowercased() == "bash" {
            short = p.count > 42 ? String(p.prefix(40)) + "…" : p
        } else {
            short = URL(fileURLWithPath: p).lastPathComponent
        }
        return "\(verb) · \(short)"
    }
}

// MARK: - Helpers

private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private extension KeyedDecodingContainer where Key == DynamicKey {
    func decode(_ key: String) -> String? {
        try? decodeIfPresent(String.self, forKey: DynamicKey(stringValue: key))
    }
}
