import Foundation
package import OICore

// MARK: - OpenCodeEventNormalizer

/// Maps OpenCode SSE events to normalized ``ProviderEvent`` values.
///
/// This is a namespace enum with static methods — it holds no state.
/// OpenCode emits 30+ event types; we map the subset relevant to Open Island
/// and silently ignore the rest.
package enum OpenCodeEventNormalizer {
    // MARK: Package

    /// Normalize an SSE event into zero or more ``ProviderEvent`` values.
    ///
    /// Returns an empty array for unknown or unmapped event types.
    package static func normalize(_ sseEvent: SSEEvent) -> [ProviderEvent] {
        guard let eventType = sseEvent.event,
              let json = parseJSON(sseEvent.data)
        else {
            return []
        }

        return self.dispatch(eventType: eventType, json: json)
    }

    // MARK: Private

    // MARK: - Event Dispatch

    /// Route an event type string to the appropriate normalizer.
    private static func dispatch(eventType: String, json: [String: Any]) -> [ProviderEvent] {
        if let events = dispatchSessionEvent(eventType: eventType, json: json) {
            return events
        }
        return self.dispatchNonSessionEvent(eventType: eventType, json: json)
    }

    private static func dispatchSessionEvent(eventType: String, json: [String: Any]) -> [ProviderEvent]? {
        switch eventType {
        case "session.created": self.normalizeSessionCreated(json)
        case "session.deleted": self.normalizeSessionDeleted(json)
        case "session.status": self.normalizeSessionStatus(json)
        case "session.idle": self.normalizeSessionIdle(json)
        case "session.compacted": self.normalizeSessionCompacted(json)
        case "session.error": self.normalizeSessionError(json)
        case "session.abort": self.normalizeSessionAbort(json)
        case "session.diff": self.normalizeSessionDiff(json)
        default: nil
        }
    }

    private static func dispatchNonSessionEvent(eventType: String, json: [String: Any]) -> [ProviderEvent] {
        switch eventType {
        case "tool.execute.before": self.normalizeToolBefore(json)
        case "tool.execute.after": self.normalizeToolAfter(json)
        case "permission.asked": self.normalizePermissionAsked(json)
        case "message.part.updated": self.normalizeMessagePartUpdated(json)
        case "message.updated": self.normalizeMessageUpdated(json)
        case "file.edited": self.normalizeFileEdited(json)
        case "plugin.call": self.normalizePluginCall(json)
        case "plugin.result": self.normalizePluginResult(json)
        default: []
        }
    }

    // MARK: - JSON Parsing

    private static func parseJSON(_ data: String) -> [String: Any]? {
        guard let jsonData = data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else {
            return nil
        }
        return obj
    }

    // MARK: - Session Events

    private static func normalizeSessionCreated(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        let directory = json["directory"] as? String ?? ""
        return [.sessionStarted(sessionID, cwd: directory, pid: nil)]
    }

    private static func normalizeSessionDeleted(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        return [.sessionEnded(sessionID)]
    }

    private static func normalizeSessionStatus(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        let status = json["status"] as? String
        if status == "processing" {
            return [.processingStarted(sessionID)]
        }
        return []
    }

    private static func normalizeSessionIdle(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        return [.waitingForInput(sessionID)]
    }

    private static func normalizeSessionCompacted(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        return [.compacting(sessionID)]
    }

    private static func normalizeSessionError(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        let message = json["error"] as? String
            ?? json["message"] as? String
            ?? "Unknown error"

        // Detect abort/interrupt patterns in error messages
        let lowered = message.lowercased()
        if lowered.contains("abort") || lowered.contains("interrupt") || lowered.contains("cancelled") {
            return [.interruptDetected(sessionID), .waitingForInput(sessionID), .notification(sessionID, message: message)]
        }
        return [.notification(sessionID, message: message)]
    }

    private static func normalizeSessionAbort(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        return [.interruptDetected(sessionID), .waitingForInput(sessionID)]
    }

    private static func normalizeSessionDiff(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        let diff = json["diff"] as? String ?? ""
        return [.diffUpdated(sessionID, unifiedDiff: diff)]
    }

    // MARK: - Tool Events

    private static func normalizeToolBefore(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        let toolEvent = self.makeToolEvent(from: json)
        return [.toolStarted(sessionID, toolEvent)]
    }

    private static func normalizeToolAfter(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        let toolEvent = self.makeToolEvent(from: json)

        let isSuccess: Bool = if let error = json["error"] {
            error is NSNull
        } else {
            true
        }

        let errorMessage: String? = if !isSuccess {
            json["error"] as? String ?? "Tool failed"
        } else {
            nil
        }

        let durationMs = json["durationMs"] as? Int
        let duration: TimeInterval? = durationMs.map { Double($0) / 1000.0 }

        let output = self.convertToJSONValue(json["result"])

        let result = ToolResult(
            output: output,
            isSuccess: isSuccess,
            duration: duration,
            errorMessage: errorMessage,
        )
        return [.toolCompleted(sessionID, toolEvent, result)]
    }

    // MARK: - Permission Events

    private static func normalizePermissionAsked(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        let requestID = json["requestId"] as? String
            ?? json["id"] as? String
            ?? UUID().uuidString

        let toolName = json["tool"] as? String
            ?? json["toolName"] as? String
            ?? "unknown"

        let toolInput = self.convertToJSONValue(json["input"] ?? json["toolInput"])

        let riskString = json["risk"] as? String
        let risk = riskString.flatMap(self.mapRisk)

        let request = PermissionRequest(
            id: requestID,
            toolName: toolName,
            toolInput: toolInput,
            timestamp: Date(),
            risk: risk,
        )
        return [.permissionRequested(sessionID, request)]
    }

    // MARK: - Message Events

    private static func normalizeMessagePartUpdated(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        guard let delta = json["delta"] as? String else {
            return []
        }
        return [.modelResponse(sessionID, textDelta: delta)]
    }

    private static func normalizeMessageUpdated(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        guard let content = json["content"] as? [[String: Any]] else {
            return []
        }

        var items: [ChatHistoryItem] = []
        for (index, part) in content.enumerated() {
            let id = part["id"] as? String ?? "\(sessionID)-msg-\(index)"
            let role = part["role"] as? String ?? "assistant"
            let text = part["text"] as? String
                ?? part["content"] as? String
                ?? ""

            let type: ChatItemType = switch role {
            case "user": .user
            case "assistant": .assistant
            case "tool": .toolCall
            case "thinking": .thinking
            default: .assistant
            }

            items.append(ChatHistoryItem(
                id: id,
                timestamp: Date(),
                type: type,
                content: text,
            ))
        }

        guard !items.isEmpty else { return [] }
        return [.chatUpdated(sessionID, items)]
    }

    // MARK: - File Events

    private static func normalizeFileEdited(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        let path = json["path"] as? String ?? "unknown"
        return [.notification(sessionID, message: "File edited: \(path)")]
    }

    // MARK: - Plugin Events (Nested Tool Detection)

    private static func normalizePluginCall(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        let taskID = json["pluginId"] as? String
            ?? json["callId"] as? String
            ?? UUID().uuidString
        let parentToolID = json["parentToolId"] as? String
        return [.subagentStarted(sessionID, taskID: taskID, parentToolID: parentToolID)]
    }

    private static func normalizePluginResult(_ json: [String: Any]) -> [ProviderEvent] {
        let sessionID = self.extractSessionID(json)
        let taskID = json["pluginId"] as? String
            ?? json["callId"] as? String
            ?? UUID().uuidString
        return [.subagentStopped(sessionID, taskID: taskID)]
    }

    // MARK: - Helpers

    private static func extractSessionID(_ json: [String: Any]) -> SessionID {
        json["sessionId"] as? String
            ?? json["session_id"] as? String
            ?? json["id"] as? String
            ?? "unknown"
    }

    private static func makeToolEvent(from json: [String: Any]) -> ToolEvent {
        let id = json["toolId"] as? String
            ?? json["id"] as? String
            ?? UUID().uuidString
        let name = json["tool"] as? String
            ?? json["toolName"] as? String
            ?? json["name"] as? String
            ?? "unknown"
        let input = self.convertToJSONValue(json["input"] ?? json["toolInput"])
        return ToolEvent(id: id, name: name, input: input, startedAt: Date())
    }

    private static func mapRisk(_ risk: String) -> PermissionRisk? {
        switch risk.lowercased() {
        case "low": .low
        case "medium": .medium
        case "high": .high
        default: nil
        }
    }

    /// Convert an arbitrary `Any?` value from `JSONSerialization` into a ``JSONValue``.
    private static func convertToJSONValue(_ value: Any?) -> JSONValue? {
        guard let value else { return nil }

        switch value {
        case is NSNull:
            return .null
        case let string as String:
            return .string(string)
        case let boolVal as Bool:
            return .bool(boolVal)
        case let intVal as Int:
            return .int(intVal)
        case let doubleVal as Double:
            return .double(doubleVal)
        case let arr as [Any]:
            return .array(arr.compactMap { self.convertToJSONValue($0) })
        case let dict as [String: Any]:
            var result: [String: JSONValue] = [:]
            for (key, val) in dict {
                result[key] = self.convertToJSONValue(val) ?? .null
            }
            return .object(result)
        default:
            return .string(String(describing: value))
        }
    }
}
