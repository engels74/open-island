public import OICore

/// The content displayed inside the opened notch panel.
public enum NotchContentType: Sendable {
    /// Grid/list of active coding-agent sessions.
    case instances
    /// Chat detail view for a specific session.
    case chat(SessionState)
    /// Settings / preferences menu.
    case menu
}
