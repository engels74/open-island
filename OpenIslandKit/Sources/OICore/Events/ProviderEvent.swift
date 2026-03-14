/// A unique identifier for a provider session.
package typealias SessionID = String

// MARK: - ProviderEvent

/// A normalized event emitted by any provider, representing all observable
/// state changes during a coding assistant session.
package enum ProviderEvent: Sendable {
    case sessionStarted(SessionID, cwd: String, pid: Int32?)
    case sessionEnded(SessionID)
    case userPromptSubmitted(SessionID)
    case processingStarted(SessionID)
    case toolStarted(SessionID, ToolEvent)
    case toolCompleted(SessionID, ToolEvent, ToolResult?)
    case permissionRequested(SessionID, PermissionRequest)
    case waitingForInput(SessionID)
    case compacting(SessionID)
    case notification(SessionID, message: String)
    case chatUpdated(SessionID, [ChatHistoryItem])
    case subagentStarted(SessionID, taskID: String, parentToolID: String?)
    case subagentStopped(SessionID, taskID: String)
    case configChanged(SessionID?)
    case diffUpdated(SessionID, unifiedDiff: String)
    case modelResponse(SessionID, textDelta: String)
    case tokenUsage(SessionID, promptTokens: Int?, completionTokens: Int?, totalTokens: Int?)
}
