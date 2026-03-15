package import OICore

// MARK: - ClaudeHookEvent

/// Raw representation of a Claude Code hook event as received from the hook socket.
///
/// Claude Code emits JSON payloads via its hook system. All events share a common set
/// of fields, with additional fields present depending on the ``hookEventName``.
package struct ClaudeHookEvent: Codable, Sendable {
    // MARK: Package

    // MARK: - Common fields (present on all events)

    /// The unique identifier for the Claude Code session.
    package let sessionID: String

    /// Filesystem path to the session transcript, if available.
    package let transcriptPath: String?

    /// Working directory of the Claude Code session.
    package let cwd: String?

    /// The active permission mode (e.g. "default", "plan", "bypassPermissions").
    package let permissionMode: String?

    /// The event type name (e.g. "PreToolUse", "SessionStart", "Stop").
    package let hookEventName: String

    // MARK: - Tool-related fields (PreToolUse, PermissionRequest, PostToolUse)

    /// Name of the tool being invoked.
    package let toolName: String?

    /// Tool invocation input parameters.
    package let toolInput: JSONValue?

    /// Unique identifier for this tool use.
    package let toolUseID: String?

    // MARK: - PostToolUse / PostToolUseFailure fields

    /// The result returned by the tool.
    package let toolResult: JSONValue?

    /// Error information from a failed tool invocation.
    package let error: JSONValue?

    // MARK: - SessionStart fields

    /// Type of session start: "startup", "resume", "clear", "compact".
    package let sessionType: String?

    // MARK: - Subagent fields

    /// Task identifier for subagent events.
    package let taskID: String?

    /// Context from the parent agent.
    package let parentContext: JSONValue?

    // MARK: - PreCompact fields

    /// Reason the context is being compacted.
    package let compactionReason: String?

    /// Number of messages in the conversation before compaction.
    package let messageCount: Int?

    // MARK: - Notification fields

    /// The type of notification (e.g. "info", "warning").
    package let notificationType: String?

    /// Human-readable notification message.
    package let message: String?

    // MARK: Private

    // MARK: - CodingKeys

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
        case compactionReason = "compaction_reason"
        case messageCount = "message_count"
        case notificationType = "notification_type"
        case message
    }
}
