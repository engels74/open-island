package import Foundation
package import OICore

// MARK: - GeminiEventNormalizer

/// Maps raw Gemini CLI hook JSON events to normalized ``ProviderEvent`` values.
package enum GeminiEventNormalizer {
    // MARK: Package

    package static func normalize(
        _ data: Data,
        lastAfterModelTime: Date?,
    ) throws(EventNormalizationError) -> (events: [ProviderEvent], updatedThrottleTime: Date?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw .malformedPayload(field: "root")
        }

        guard let hookEventName = json["hook_event_name"] as? String else {
            throw .missingRequiredField("hook_event_name")
        }

        guard let sessionID = json["session_id"] as? String else {
            throw .missingRequiredField("session_id")
        }

        return try self.dispatchHookEvent(hookEventName, json: json, sessionID: sessionID, lastAfterModelTime: lastAfterModelTime)
    }

    // MARK: Private

    // MARK: - MCP Context Detection

    private enum ToolPhase { case before, after }

    private static let afterModelThrottleInterval: TimeInterval = 0.1

    // MARK: - Hook Event Dispatch

    private static func dispatchHookEvent(
        _ hookEventName: String,
        json: [String: Any],
        sessionID: String,
        lastAfterModelTime: Date?,
    ) throws(EventNormalizationError) -> (events: [ProviderEvent], updatedThrottleTime: Date?) {
        switch hookEventName {
        case "SessionStart":
            let cwd = json["cwd"] as? String ?? ""
            return ([.sessionStarted(sessionID, cwd: cwd, pid: nil)], lastAfterModelTime)

        case "SessionEnd":
            return ([.sessionEnded(sessionID)], lastAfterModelTime)

        case "BeforeAgent":
            return (
                [.userPromptSubmitted(sessionID), .processingStarted(sessionID)],
                lastAfterModelTime,
            )

        case "AfterAgent":
            return self.normalizeAfterAgent(json, sessionID: sessionID, lastAfterModelTime: lastAfterModelTime)

        case "BeforeTool":
            let mcpEvents = self.normalizeMCPContext(json, sessionID: sessionID, phase: .before)
            let toolEvent = try makeToolEvent(from: json, sessionID: sessionID)
            return (mcpEvents + [.toolStarted(sessionID, toolEvent)], lastAfterModelTime)

        case "AfterTool":
            let toolEvent = try makeToolEvent(from: json, sessionID: sessionID)
            let result = self.makeToolResult(from: json)
            let mcpEvents = self.normalizeMCPContext(json, sessionID: sessionID, phase: .after)
            return ([.toolCompleted(sessionID, toolEvent, result)] + mcpEvents, lastAfterModelTime)

        case "BeforeModel":
            return ([.processingStarted(sessionID)], lastAfterModelTime)

        case "AfterModel":
            return self.normalizeAfterModel(json, sessionID: sessionID, lastAfterModelTime: lastAfterModelTime)

        case "BeforeToolSelection":
            return ([], lastAfterModelTime)

        case "BeforeSubagent":
            return (self.normalizeBeforeSubagent(json, sessionID: sessionID), lastAfterModelTime)

        case "AfterSubagent":
            return (self.normalizeAfterSubagent(json, sessionID: sessionID), lastAfterModelTime)

        case "PreCompress":
            return ([.compacting(sessionID)], lastAfterModelTime)

        case "Notification":
            return try self.normalizeNotification(json, sessionID: sessionID, lastAfterModelTime: lastAfterModelTime)

        default:
            throw .unknownEventType(hookEventName)
        }
    }

    private static func normalizeAfterAgent(
        _ json: [String: Any],
        sessionID: String,
        lastAfterModelTime: Date?,
    ) -> (events: [ProviderEvent], updatedThrottleTime: Date?) {
        var events: [ProviderEvent] = []
        let interrupted = json["interrupted"] as? Bool ?? false
        let reason = json["reason"] as? String
        if interrupted || reason == "interrupted" {
            events.append(.interruptDetected(sessionID))
        }
        events.append(.waitingForInput(sessionID))
        return (events, lastAfterModelTime)
    }

    // MARK: - AfterModel Normalization (with throttling)

    private static func normalizeAfterModel(
        _ json: [String: Any],
        sessionID: SessionID,
        lastAfterModelTime: Date?,
    ) -> (events: [ProviderEvent], updatedThrottleTime: Date?) {
        let now = Date()
        var events: [ProviderEvent] = []

        let shouldEmit = if let lastTime = lastAfterModelTime {
            now.timeIntervalSince(lastTime) >= self.afterModelThrottleInterval
        } else {
            true
        }

        if shouldEmit {
            let textDelta = self.extractTextDelta(from: json)
            events.append(.modelResponse(sessionID, textDelta: textDelta))
        }

        if let usageMetadata = json["usageMetadata"] as? [String: Any],
           let totalTokenCount = usageMetadata["totalTokenCount"] as? Int {
            let promptTokens = usageMetadata["promptTokenCount"] as? Int
            let completionTokens = usageMetadata["candidatesTokenCount"] as? Int
            events.append(.tokenUsage(
                sessionID,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokenCount,
            ))
        }

        let updatedTime = shouldEmit ? now : lastAfterModelTime
        return (events, updatedTime)
    }

    private static func extractTextDelta(from json: [String: Any]) -> String {
        if let text = json["text"] as? String {
            return text
        }
        if let response = json["response"] as? [String: Any],
           let text = response["text"] as? String {
            return text
        }
        if let candidates = json["candidates"] as? [[String: Any]],
           let firstCandidate = candidates.first,
           let content = firstCandidate["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let firstPart = parts.first,
           let text = firstPart["text"] as? String {
            return text
        }
        return ""
    }

    // MARK: - Notification Normalization

    private static func normalizeNotification(
        _ json: [String: Any],
        sessionID: SessionID,
        lastAfterModelTime: Date?,
    ) throws(EventNormalizationError) -> (events: [ProviderEvent], updatedThrottleTime: Date?) {
        let notificationType = json["notification_type"] as? String

        if notificationType == "ToolPermission" {
            // ToolPermission notifications drive the UI approval flow.
            // The request ID must match the composite key used by
            // GeminiBridgeDelegate.extractRequestID for BeforeTool socket
            // connections, so respondToPermission can find the held-open socket.
            let toolName = json["tool_name"] as? String ?? "unknown"
            let timestamp = json["timestamp"] as? String ?? "unknown"
            let requestID = "\(sessionID):\(toolName):\(timestamp)"
            let toolInput = self.convertToJSONValue(json["tool_input"])

            let request = PermissionRequest(
                id: requestID,
                toolName: toolName,
                toolInput: toolInput,
                timestamp: Date(),
            )
            return ([.permissionRequested(sessionID, request)], lastAfterModelTime)
        }

        let message = json["message"] as? String ?? json["notification_type"] as? String ?? ""
        return ([.notification(sessionID, message: message)], lastAfterModelTime)
    }

    // MARK: - Subagent Normalization

    private static func normalizeBeforeSubagent(
        _ json: [String: Any],
        sessionID: SessionID,
    ) -> [ProviderEvent] {
        let taskID = json["task_id"] as? String
            ?? json["subagent_id"] as? String
            ?? "unknown"
        let parentToolID = json["parent_tool_id"] as? String
        return [.subagentStarted(sessionID, taskID: taskID, parentToolID: parentToolID)]
    }

    private static func normalizeAfterSubagent(
        _ json: [String: Any],
        sessionID: SessionID,
    ) -> [ProviderEvent] {
        let taskID = json["task_id"] as? String
            ?? json["subagent_id"] as? String
            ?? "unknown"
        return [.subagentStopped(sessionID, taskID: taskID)]
    }

    /// Detect MCP tool calls with `mcp_context` field indicating nesting.
    /// When present, emits subagent start/stop events around the tool call.
    private static func normalizeMCPContext(
        _ json: [String: Any],
        sessionID: SessionID,
        phase: ToolPhase,
    ) -> [ProviderEvent] {
        guard let mcpContext = json["mcp_context"] as? [String: Any] else {
            return []
        }
        let taskID = mcpContext["server_id"] as? String
            ?? mcpContext["session_id"] as? String
            ?? "unknown"
        let parentToolID = mcpContext["parent_tool_id"] as? String

        switch phase {
        case .before:
            return [.subagentStarted(sessionID, taskID: taskID, parentToolID: parentToolID)]
        case .after:
            return [.subagentStopped(sessionID, taskID: taskID)]
        }
    }

    // MARK: - Tool Event Construction

    private static func makeToolEvent(
        from json: [String: Any],
        sessionID: SessionID,
    ) throws(EventNormalizationError) -> ToolEvent {
        guard let toolName = json["tool_name"] as? String else {
            throw .missingRequiredField("tool_name")
        }

        let timestamp = json["timestamp"] as? String ?? "unknown"
        let toolUseID = "\(sessionID):\(toolName):\(timestamp)"

        let toolInput = self.convertToJSONValue(json["tool_input"])

        return ToolEvent(
            id: toolUseID,
            name: toolName,
            input: toolInput,
            startedAt: Date(),
        )
    }

    private static func makeToolResult(from json: [String: Any]) -> ToolResult {
        let toolResponse = json["tool_response"] as? [String: Any]
        let output = self.convertToJSONValue(toolResponse?["llmContent"])
        let errorString = toolResponse?["error"] as? String
        let isSuccess = errorString == nil

        return ToolResult(
            output: output,
            isSuccess: isSuccess,
            errorMessage: errorString,
        )
    }

    // MARK: - JSON Conversion Utilities

    private static func convertToJSONValue(_ value: Any?) -> JSONValue? {
        guard let value else { return nil }

        switch value {
        case is NSNull:
            return .null
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            // CFBoolean check must come before numeric checks because
            // NSNumber wraps both booleans and numbers.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            if let int = value as? Int, Double(int) == number.doubleValue {
                return .int(int)
            }
            return .double(number.doubleValue)
        case let array as [Any]:
            return .array(array.compactMap { self.convertToJSONValue($0) })
        case let dict as [String: Any]:
            var result: [String: JSONValue] = [:]
            for (key, val) in dict {
                if let jsonVal = convertToJSONValue(val) {
                    result[key] = jsonVal
                }
            }
            return .object(result)
        default:
            return .string(String(describing: value))
        }
    }
}
