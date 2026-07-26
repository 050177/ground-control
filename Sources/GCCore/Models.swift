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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        sessionId      = c.decode("session_id") ?? ""
        event          = c.decode("hook_event_name") ?? ""
        cwd            = c.decode("cwd")
        permissionMode = c.decode("permission_mode")
        transcriptPath = c.decode("transcript_path")
        // "prompt" is the actual field name in claude 2.x; fall back to older names
        message = c.decode("prompt") ?? c.decode("message") ?? c.decode("user_message") ?? c.decode("input")
    }

    public init(sessionId: String, event: String, cwd: String? = nil,
                permissionMode: String? = nil, message: String? = nil, transcriptPath: String? = nil) {
        self.sessionId      = sessionId
        self.event          = event
        self.cwd            = cwd
        self.permissionMode = permissionMode
        self.message        = message
        self.transcriptPath = transcriptPath
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
