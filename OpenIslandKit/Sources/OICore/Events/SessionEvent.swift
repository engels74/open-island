// MARK: - SessionEvent

/// An internal event for ``SessionStore``, encompassing provider events
/// and UI-initiated actions.
package enum SessionEvent: Sendable {
    case providerEvent(ProviderEvent)
    case permissionApproved(SessionID, requestID: String)
    case permissionDenied(SessionID, requestID: String, reason: String?)
    case archiveSession(SessionID)
    case userAction(SessionID, action: UserAction)
}

// MARK: - UserAction

/// Actions initiated by the user through the UI.
package enum UserAction: Sendable {
    case scrollToBottom
    case copyToClipboard(String)
    case cancelOperation
}
