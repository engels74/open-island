/// Why the notch panel is being opened.
///
/// Mirrors `OIWindow.OpenReason` but lives in OIUI to avoid
/// tight coupling between the UI layer and the window layer.
public enum NotchOpenReason: Sendable {
    case click
    case hover
    case notification
    case permissionRequest
    case boot
}
