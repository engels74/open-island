package import Foundation
package import OICore

// MARK: - ClaudeEventNormalizer

/// Maps raw ``ClaudeHookEvent`` payloads to normalized ``ProviderEvent`` values.
///
/// This is a namespace enum with static methods — it holds no state.
package enum ClaudeEventNormalizer {
    // MARK: Package

    /// Normalize a raw Claude hook event into a ``ProviderEvent``.
    ///
    /// Returns `nil` for events that have no meaningful ``ProviderEvent`` equivalent
    /// (e.g. `Setup`, `WorktreeCreate`, `WorktreeRemove`).
    ///
    /// - Throws: ``EventNormalizationError`` for unknown event types or malformed payloads.
    package static func normalize(_ event: ClaudeHookEvent) throws(EventNormalizationError) -> ProviderEvent? {
        switch event.hookEventName {
        case "Setup",
             "TeammateIdle",
             "TaskCompleted",
             "WorktreeCreate",
             "WorktreeRemove":
            return nil
        case "SessionStart",
             "SessionEnd",
             "UserPromptSubmit",
             "Stop",
             "PreCompact",
             "ConfigChange",
             "Notification":
            return self.normalizeSession(event)
        case "PreToolUse",
             "PostToolUse",
             "PostToolUseFailure",
             "PermissionRequest":
            return try self.normalizeTool(event)
        case "SubagentStart",
             "SubagentStop":
            return try self.normalizeSubagent(event)
        default:
            throw .unknownEventType(event.hookEventName)
        }
    }

    // MARK: Private

    private static func normalizeSession(_ event: ClaudeHookEvent) -> ProviderEvent {
        let sid = event.sessionID
        switch event.hookEventName {
        case "SessionStart":
            return .sessionStarted(sid, cwd: event.cwd ?? "", pid: nil)
        case "SessionEnd":
            return .sessionEnded(sid)
        case "UserPromptSubmit":
            return .userPromptSubmitted(sid)
        case "Stop":
            return .waitingForInput(sid)
        case "PreCompact":
            return .compacting(sid)
        case "ConfigChange":
            return .configChanged(sid)
        case "Notification":
            return .notification(sid, message: event.message ?? "")
        default:
            fatalError("Unreachable: \(event.hookEventName) not a session event")
        }
    }

    private static func normalizeTool(
        _ event: ClaudeHookEvent,
    ) throws(EventNormalizationError) -> ProviderEvent {
        let sid = event.sessionID
        switch event.hookEventName {
        case "PreToolUse":
            let toolEvent = try makeToolEvent(from: event)
            return .toolStarted(sid, toolEvent)
        case "PostToolUse":
            let toolEvent = try makeToolEvent(from: event)
            let result = self.makeToolResult(from: event, isSuccess: true)
            return .toolCompleted(sid, toolEvent, result)
        case "PostToolUseFailure":
            let toolEvent = try makeToolEvent(from: event)
            let result = self.makeToolResult(from: event, isSuccess: false)
            return .toolCompleted(sid, toolEvent, result)
        case "PermissionRequest":
            let request = try makePermissionRequest(from: event)
            return .permissionRequested(sid, request)
        default:
            fatalError("Unreachable: \(event.hookEventName) not a tool event")
        }
    }

    private static func normalizeSubagent(
        _ event: ClaudeHookEvent,
    ) throws(EventNormalizationError) -> ProviderEvent {
        let sid = event.sessionID
        guard let taskID = event.taskID else {
            throw .missingRequiredField("task_id")
        }
        switch event.hookEventName {
        case "SubagentStart":
            return .subagentStarted(sid, taskID: taskID, parentToolID: nil)
        case "SubagentStop":
            return .subagentStopped(sid, taskID: taskID)
        default:
            fatalError("Unreachable: \(event.hookEventName) not a subagent event")
        }
    }

    private static func makeToolEvent(from event: ClaudeHookEvent) throws(EventNormalizationError) -> ToolEvent {
        guard let toolName = event.toolName else {
            throw .missingRequiredField("tool_name")
        }
        let toolUseID = event.toolUseID ?? UUID().uuidString
        return ToolEvent(
            id: toolUseID,
            name: toolName,
            input: event.toolInput,
            startedAt: Date(),
        )
    }

    private static func makeToolResult(from event: ClaudeHookEvent, isSuccess: Bool) -> ToolResult {
        let errorMessage: String? = if !isSuccess {
            event.error?.stringValue ?? (event.error != nil ? "Tool failed" : nil)
        } else {
            nil
        }
        return ToolResult(
            output: event.toolResult,
            isSuccess: isSuccess,
            errorMessage: errorMessage,
        )
    }

    private static func makePermissionRequest(
        from event: ClaudeHookEvent,
    ) throws(EventNormalizationError) -> PermissionRequest {
        guard let toolName = event.toolName else {
            throw .missingRequiredField("tool_name")
        }
        let id = event.toolUseID ?? UUID().uuidString
        return PermissionRequest(
            id: id,
            toolName: toolName,
            toolInput: event.toolInput,
            timestamp: Date(),
        )
    }
}
