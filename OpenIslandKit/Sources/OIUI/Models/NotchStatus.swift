/// The visual state of the notch panel.
public enum NotchStatus: Sendable {
    /// Panel is hidden; only the closed-state header modules are visible.
    case closed
    /// Panel is fully expanded showing content.
    case opened
    /// Transient "pop" animation state (e.g. notification bounce).
    case popping
}
