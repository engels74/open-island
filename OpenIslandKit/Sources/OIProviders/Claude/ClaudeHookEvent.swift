package import OICore

// MARK: - ClaudeHookEvent

/// Raw representation of a Claude Code hook event as received from the hook socket.
///
/// Claude Code emits JSON payloads via its hook system. All events share a common set
/// of fields, with additional fields present depending on the ``hookEventName``.
package struct ClaudeHookEvent: Codable, Sendable {
    // MARK: Package

    package let sessionID: String
    package let transcriptPath: String?
    package let cwd: String?
    package let permissionMode: String?
    package let hookEventName: String

    package let toolName: String?
    package let toolInput: JSONValue?
    package let toolUseID: String?

    package let toolResult: JSONValue?
    package let error: JSONValue?

    package let sessionType: String?

    package let taskID: String?
    package let parentContext: JSONValue?

    package let teammateSessionID: String?
    package let taskResult: JSONValue?

    package let compactionReason: String?
    package let messageCount: Int?

    package let stopReason: String?

    package let notificationType: String?
    package let message: String?

    package let filePath: String?
    package let memoryType: String?

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
        case cwd
        case permissionMode = "permission_mode"
        case hookEventName = "hook_event_name"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseID = "tool_use_id"
        case toolResult = "tool_result"
        case error
        case sessionType = "session_type"
        case taskID = "task_id"
        case parentContext = "parent_context"
        case teammateSessionID = "teammate_session_id"
        case taskResult = "task_result"
        case compactionReason = "compaction_reason"
        case messageCount = "message_count"
        case stopReason = "stop_reason"
        case notificationType = "notification_type"
        case message
        case filePath = "file_path"
        case memoryType = "memory_type"
    }
}
