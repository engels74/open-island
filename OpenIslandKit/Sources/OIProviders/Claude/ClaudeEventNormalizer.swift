package import Foundation
package import OICore

// MARK: - ClaudeEventNormalizer

/// Maps raw ``ClaudeHookEvent`` payloads to normalized ``ProviderEvent`` values.
///
/// This is a namespace enum with static methods — it holds no state.
package enum ClaudeEventNormalizer {
    // MARK: Package

    package static func normalize(_ event: ClaudeHookEvent) throws(EventNormalizationError) -> [ProviderEvent] {
        switch event.hookEventName {
        case "Setup",
             "WorktreeCreate",
             "WorktreeRemove":
            return []
        case "TeammateIdle":
            return self.normalizeTeammateIdle(event)
        case "TaskCompleted":
            return try self.normalizeTaskCompleted(event)
        case "SessionStart",
             "SessionEnd",
             "UserPromptSubmit",
             "Stop",
             "StopFailure",
             "PreCompact",
             "PostCompact",
             "ConfigChange",
             "Notification",
             "InstructionsLoaded",
             "Elicitation",
             "ElicitationResult":
            return self.normalizeSession(event)
        case "PreToolUse",
             "PostToolUse",
             "PostToolUseFailure",
             "PermissionRequest":
            return try [self.normalizeTool(event)]
        case "SubagentStart",
             "SubagentStop":
            return try [self.normalizeSubagent(event)]
        default:
            throw .unknownEventType(event.hookEventName)
        }
    }

    // MARK: Private

    private static func normalizeSession(_ event: ClaudeHookEvent) -> [ProviderEvent] {
        let sid = event.sessionID
        switch event.hookEventName {
        case "SessionStart":
            return [.sessionStarted(sid, providerID: .claude, cwd: event.cwd ?? "", pid: nil)]
        case "SessionEnd":
            return [.sessionEnded(sid)]
        case "UserPromptSubmit":
            return [.userPromptSubmitted(sid)]
        case "Stop":
            var events: [ProviderEvent] = []
            if event.stopReason == "interrupted" {
                events.append(.interruptDetected(sid))
            }
            events.append(.waitingForInput(sid))
            return events
        case "StopFailure":
            let reason = event.stopReason ?? event.message ?? "unknown error"
            return [.notification(sid, message: "Turn ended with error: \(reason)")]
        case "PreCompact":
            return [.compacting(sid)]
        case "PostCompact":
            return [.notification(sid, message: "Context compacted")]
        case "ConfigChange":
            return [.configChanged(sid)]
        case "Notification":
            return [.notification(sid, message: event.message ?? "")]
        case "InstructionsLoaded":
            let detail = event.filePath ?? event.message ?? "instructions"
            return [.notification(sid, message: "Instructions loaded: \(detail)")]
        case "Elicitation":
            return [.notification(sid, message: "Elicitation: \(event.message ?? "user input requested")")]
        case "ElicitationResult":
            return [.notification(sid, message: "Elicitation completed")]
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
            let request = try self.makePermissionRequest(from: event)
            return .permissionRequested(sid, request)
        case "PostToolUse":
            let toolEvent = try makeToolEvent(from: event)
            let result = self.makeToolResult(from: event, isSuccess: true)
            return .toolCompleted(sid, toolEvent, result)
        case "PostToolUseFailure":
            let toolEvent = try makeToolEvent(from: event)
            let result = self.makeToolResult(from: event, isSuccess: false)
            return .toolCompleted(sid, toolEvent, result)
        case "PermissionRequest":
            let request = try self.makePermissionRequest(from: event)
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
            let parentToolID = self.extractParentToolID(from: event.parentContext)
            return .subagentStarted(sid, taskID: taskID, parentToolID: parentToolID)
        case "SubagentStop":
            return .subagentStopped(sid, taskID: taskID)
        default:
            fatalError("Unreachable: \(event.hookEventName) not a subagent event")
        }
    }

    private static func normalizeTeammateIdle(_ event: ClaudeHookEvent) -> [ProviderEvent] {
        let sid = event.sessionID
        let message = event.teammateSessionID.map { "Teammate \($0) idle" } ?? "Teammate idle"
        return [.notification(sid, message: message)]
    }

    private static func normalizeTaskCompleted(
        _ event: ClaudeHookEvent,
    ) throws(EventNormalizationError) -> [ProviderEvent] {
        let sid = event.sessionID
        guard let taskID = event.taskID else {
            throw .missingRequiredField("task_id")
        }
        return [.subagentStopped(sid, taskID: taskID)]
    }

    private static func extractParentToolID(from parentContext: JSONValue?) -> String? {
        guard case let .object(dict) = parentContext else { return nil }
        if case let .string(toolID) = dict["tool_use_id"] {
            return toolID
        }
        if case let .string(toolID) = dict["toolId"] {
            return toolID
        }
        return nil
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
