/// Why the notch panel is being opened.
///
/// Mirrors `OIWindow.OpenReason` but lives in OIUI to avoid
/// tight coupling between the UI layer and the window layer.
package enum NotchOpenReason: Sendable {
    /// User clicked the notch area.
    case click
    /// Mouse hovered over the notch.
    case hover
    /// A notification triggered the open.
    case notification
    /// First-launch animation.
    case boot
}
