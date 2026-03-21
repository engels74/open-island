/// A unique identifier for a provider session.
public typealias SessionID = String

// MARK: - ProviderEvent

/// A normalized event emitted by any provider, representing all observable
/// state changes during a coding assistant session.
public enum ProviderEvent: Sendable {
    case sessionStarted(SessionID, providerID: ProviderID, cwd: String, pid: Int32?)
    case sessionEnded(SessionID)
    case userPromptSubmitted(SessionID)
    case processingStarted(SessionID)
    case toolStarted(SessionID, ToolEvent)
    case toolCompleted(SessionID, ToolEvent, ToolResult?)
    case permissionRequested(SessionID, PermissionRequest)
    case waitingForInput(SessionID)
    /// The provider is compacting its context window to stay within token limits.
    case compacting(SessionID)
    case notification(SessionID, message: String)
    case chatUpdated(SessionID, [ChatHistoryItem])
    case subagentStarted(SessionID, taskID: String, parentToolID: String?)
    case subagentStopped(SessionID, taskID: String)
    /// `nil` session ID indicates a global config change affecting all sessions.
    case configChanged(SessionID?)
    case diffUpdated(SessionID, unifiedDiff: String)
    case modelResponse(SessionID, textDelta: String)
    case tokenUsage(SessionID, promptTokens: Int?, completionTokens: Int?, totalTokens: Int?)
    /// The user interrupted the provider (e.g., Ctrl+C / Escape).
    case interruptDetected(SessionID)

    // MARK: Public

    /// Extracts the session ID from any event case.
    /// Returns `nil` for `.configChanged(nil)` (global config).
    public var sessionID: SessionID? {
        switch self {
        case let .sessionStarted(id, providerID: _, cwd: _, pid: _),
             let .sessionEnded(id),
             let .userPromptSubmitted(id),
             let .processingStarted(id),
             let .toolStarted(id, _),
             let .toolCompleted(id, _, _),
             let .permissionRequested(id, _),
             let .waitingForInput(id),
             let .compacting(id),
             let .notification(id, message: _),
             let .chatUpdated(id, _),
             let .subagentStarted(id, taskID: _, parentToolID: _),
             let .subagentStopped(id, taskID: _),
             let .diffUpdated(id, unifiedDiff: _),
             let .modelResponse(id, textDelta: _),
             let .tokenUsage(id, promptTokens: _, completionTokens: _, totalTokens: _),
             let .interruptDetected(id):
            id
        case let .configChanged(id):
            id
        }
    }
}
