import Foundation
package import OICore

// MARK: - CodexEventNormalizer

/// Maps Codex JSON-RPC notifications and server-initiated requests to normalized ``ProviderEvent`` values.
///
/// This is a namespace enum with static methods — it holds no state.
/// The normalizer handles two input types:
/// - ``JSONRPCNotification``: server→client notifications (turn lifecycle, item events, streaming deltas)
/// - ``ServerInitiatedRequest``: server→client requests requiring a response (approval interception)
package enum CodexEventNormalizer {
    // MARK: Package

    /// Normalize a JSON-RPC notification into a ``ProviderEvent``.
    ///
    /// Returns `nil` for notifications that have no meaningful ``ProviderEvent`` equivalent.
    ///
    /// - Parameters:
    ///   - notification: The JSON-RPC notification from the app-server.
    ///   - sessionID: The current session identifier.
    /// - Throws: ``EventNormalizationError`` for unknown methods or malformed payloads.
    package static func normalize(
        _ notification: JSONRPCNotification,
        sessionID: SessionID,
    ) throws(EventNormalizationError) -> [ProviderEvent] {
        guard let method = CodexServerNotification(rawValue: notification.method) else {
            throw .unknownEventType(notification.method)
        }

        switch method {
        case .turnStarted:
            return [.processingStarted(sessionID)]

        case .turnCompleted:
            return self.normalizeTurnCompleted(notification.params, sessionID: sessionID)

        case .itemStarted:
            return try self.normalizeItemStarted(notification.params, sessionID: sessionID)

        case .itemCompleted:
            return try self.normalizeItemCompleted(notification.params, sessionID: sessionID)

        case .agentMessageDelta:
            let delta = self.extractString(notification.params, key: "delta") ?? ""
            return [.modelResponse(sessionID, textDelta: delta)]

        case .turnDiffUpdated:
            let diff = self.extractString(notification.params, key: "diff") ?? ""
            return [.diffUpdated(sessionID, unifiedDiff: diff)]

        case .turnPlanUpdated:
            // Plan updates don't have a direct ProviderEvent mapping
            return []

        case .reasoningSummaryTextDelta,
             .commandExecutionOutputDelta:
            // Streaming deltas for reasoning and command output — no direct mapping
            return []
        }
    }

    /// Normalize a server-initiated request (approval interception) into a ``ProviderEvent``.
    ///
    /// - Parameters:
    ///   - request: The server-initiated request from the app-server.
    ///   - sessionID: The current session identifier.
    /// - Throws: ``EventNormalizationError`` for unknown methods or malformed payloads.
    package static func normalizeServerRequest(
        _ request: ServerInitiatedRequest,
        sessionID: SessionID,
    ) throws(EventNormalizationError) -> ProviderEvent {
        guard let method = CodexServerRequest(rawValue: request.method) else {
            throw .unknownEventType(request.method)
        }

        switch method {
        case .commandExecutionRequestApproval:
            let permRequest = self.makeCommandApprovalRequest(
                from: request.params,
                requestID: request.id,
            )
            return .permissionRequested(sessionID, permRequest)

        case .fileChangeRequestApproval:
            let permRequest = self.makeFileChangeApprovalRequest(
                from: request.params,
                requestID: request.id,
            )
            return .permissionRequested(sessionID, permRequest)
        }
    }

    // MARK: Private

    // MARK: - Turn Lifecycle

    private static func normalizeTurnCompleted(
        _ params: JSONValue?,
        sessionID: SessionID,
    ) -> [ProviderEvent] {
        var events: [ProviderEvent] = []

        // Extract token usage if available
        if let params {
            let promptTokens = self.extractInt(params, key: "prompt_tokens")
            let completionTokens = self.extractInt(params, key: "completion_tokens")
            let totalTokens = self.extractInt(params, key: "total_tokens")

            if promptTokens != nil || completionTokens != nil || totalTokens != nil {
                events.append(.tokenUsage(
                    sessionID,
                    promptTokens: promptTokens,
                    completionTokens: completionTokens,
                    totalTokens: totalTokens,
                ))
            }
        }

        // Check if the turn was interrupted
        let status = self.extractString(params, key: "status")
        if status == CodexTurnStatus.interrupted.rawValue {
            events.append(.interruptDetected(sessionID))
        }

        events.append(.waitingForInput(sessionID))
        return events
    }

    // MARK: - Item Lifecycle

    private static func normalizeItemStarted(
        _ params: JSONValue?,
        sessionID: SessionID,
    ) throws(EventNormalizationError) -> [ProviderEvent] {
        guard let itemType = extractItemType(from: params) else {
            throw .missingRequiredField("type")
        }

        switch itemType {
        case .commandExecution:
            let toolEvent = self.makeToolEvent(from: params, toolName: "commandExecution")
            return [.toolStarted(sessionID, toolEvent)]

        case .fileChange:
            let toolEvent = self.makeToolEvent(from: params, toolName: "fileChange")
            return [.toolStarted(sessionID, toolEvent)]

        case .mcpToolCall:
            let tool = self.extractString(params, key: "tool") ?? "mcp"
            let server = self.extractString(params, key: "server")
            let toolName = if let server { "mcp(\(server)): \(tool)" } else { tool }
            let toolEvent = self.makeToolEvent(from: params, toolName: toolName)
            return [.toolStarted(sessionID, toolEvent)]

        case .collabToolCall:
            let taskID = self.extractString(params, key: "taskId") ?? self.extractString(params, key: "itemId") ?? UUID().uuidString
            let parentToolID = self.extractString(params, key: "parentToolId")
            return [.subagentStarted(sessionID, taskID: taskID, parentToolID: parentToolID)]

        case .userMessage,
             .agentMessage,
             .reasoning,
             .webSearch,
             .imageView,
             .enteredReviewMode,
             .compacted:
            return []
        }
    }

    private static func normalizeItemCompleted(
        _ params: JSONValue?,
        sessionID: SessionID,
    ) throws(EventNormalizationError) -> [ProviderEvent] {
        guard let itemType = extractItemType(from: params) else {
            throw .missingRequiredField("type")
        }

        switch itemType {
        case .commandExecution:
            let toolEvent = self.makeToolEvent(from: params, toolName: "commandExecution")
            let exitCode = self.extractInt(params, key: "exitCode")
            let durationMs = self.extractInt(params, key: "durationMs")
            let duration: TimeInterval? = durationMs.map { Double($0) / 1000.0 }
            let isSuccess = exitCode.map { $0 == 0 } ?? true
            let result = ToolResult(
                output: extractValue(params, key: "output"),
                isSuccess: isSuccess,
                duration: duration,
                errorMessage: isSuccess ? nil : "Exit code: \(exitCode ?? -1)",
            )
            return [.toolCompleted(sessionID, toolEvent, result)]

        case .fileChange:
            let toolEvent = self.makeToolEvent(from: params, toolName: "fileChange")
            let result = ToolResult(
                output: extractValue(params, key: "diff"),
                isSuccess: true,
            )
            return [.toolCompleted(sessionID, toolEvent, result)]

        case .mcpToolCall:
            let tool = self.extractString(params, key: "tool") ?? "mcp"
            let server = self.extractString(params, key: "server")
            let toolName = if let server { "mcp(\(server)): \(tool)" } else { tool }
            let toolEvent = self.makeToolEvent(from: params, toolName: toolName)
            let result = ToolResult(
                output: extractValue(params, key: "result"),
                isSuccess: true,
            )
            return [.toolCompleted(sessionID, toolEvent, result)]

        case .collabToolCall:
            let taskID = self.extractString(params, key: "taskId") ?? self.extractString(params, key: "itemId") ?? UUID().uuidString
            return [.subagentStopped(sessionID, taskID: taskID)]

        case .compacted:
            return [.compacting(sessionID)]

        case .userMessage,
             .agentMessage,
             .reasoning,
             .webSearch,
             .imageView,
             .enteredReviewMode:
            return []
        }
    }

    // MARK: - Approval Requests

    private static func makeCommandApprovalRequest(
        from params: JSONValue?,
        requestID: JSONRPCRequestID,
    ) -> PermissionRequest {
        let itemID = self.extractString(params, key: "item_id") ?? requestID.stringRepresentation
        let riskString = self.extractString(params, key: "risk")
        let risk = riskString.flatMap(self.mapRisk)

        return PermissionRequest(
            id: itemID,
            toolName: "commandExecution",
            toolInput: self.extractValue(params, key: "parsed_cmd"),
            timestamp: Date(),
            risk: risk,
        )
    }

    private static func makeFileChangeApprovalRequest(
        from params: JSONValue?,
        requestID: JSONRPCRequestID,
    ) -> PermissionRequest {
        let itemID = self.extractString(params, key: "item_id") ?? requestID.stringRepresentation
        let path = self.extractString(params, key: "path")
        let kind = self.extractString(params, key: "kind")

        // Encode path and kind as tool input
        var inputDict: [String: JSONValue] = [:]
        if let path { inputDict["path"] = .string(path) }
        if let kind { inputDict["kind"] = .string(kind) }
        let toolInput: JSONValue? = inputDict.isEmpty ? nil : .object(inputDict)

        return PermissionRequest(
            id: itemID,
            toolName: "fileChange",
            toolInput: toolInput,
            timestamp: Date(),
        )
    }

    // MARK: - Helpers

    private static func extractItemType(from params: JSONValue?) -> CodexThreadItemType? {
        guard let typeString = extractString(params, key: "type") else { return nil }
        return CodexThreadItemType(rawValue: typeString)
    }

    private static func makeToolEvent(from params: JSONValue?, toolName: String) -> ToolEvent {
        let id = self.extractString(params, key: "itemId") ?? UUID().uuidString
        var input: JSONValue?
        if let command = extractString(params, key: "command") {
            input = .string(command)
        } else if let path = extractString(params, key: "path") {
            let kind = self.extractString(params, key: "kind") ?? "modify"
            input = .object(["path": .string(path), "kind": .string(kind)])
        } else if let arguments = extractValue(params, key: "arguments") {
            input = arguments
        }
        return ToolEvent(id: id, name: toolName, input: input, startedAt: Date())
    }

    private static func mapRisk(_ risk: String) -> PermissionRisk? {
        switch risk.lowercased() {
        case "low": .low
        case "medium": .medium
        case "high": .high
        default: nil
        }
    }

    // MARK: - JSONValue Extraction Utilities

    private static func extractString(_ value: JSONValue?, key: String) -> String? {
        guard case let .object(dict) = value, case let .string(str) = dict[key] else { return nil }
        return str
    }

    private static func extractInt(_ value: JSONValue?, key: String) -> Int? {
        guard case let .object(dict) = value else { return nil }
        switch dict[key] {
        case let .int(intVal): return intVal
        case let .double(doubleVal): return Int(doubleVal)
        default: return nil
        }
    }

    private static func extractValue(_ value: JSONValue?, key: String) -> JSONValue? {
        guard case let .object(dict) = value else { return nil }
        return dict[key]
    }

    /// Overload for extracting from a non-optional JSONValue.
    private static func extractInt(_ value: JSONValue, key: String) -> Int? {
        switch value {
        case let .object(dict):
            switch dict[key] {
            case let .int(intVal): intVal
            case let .double(doubleVal): Int(doubleVal)
            default: nil
            }
        default: nil
        }
    }
}
