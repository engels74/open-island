@preconcurrency package import AppKit

// MARK: - ScreenIdentifier

/// A persistent identifier for a display, used to remember a user's screen selection.
///
/// Wraps `CGDirectDisplayID` with `Codable` support for storage in `UserDefaults`.
package struct ScreenIdentifier: Sendable, Equatable, Hashable, Codable {
    // MARK: Lifecycle

    package init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    /// Creates a `ScreenIdentifier` from an `NSScreen`, if the screen has a valid display ID.
    package init?(screen: NSScreen) {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        self.displayID = id
    }

    // MARK: Package

    /// The underlying Core Graphics display ID.
    package let displayID: UInt32

    /// Resolves this identifier to a currently connected `NSScreen`, or `nil` if disconnected.
    package func resolve() -> NSScreen? {
        NSScreen.screens.first { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return id == self.displayID
        }
    }
}

// MARK: - ScreenSelector

/// Determines which screen to use for the notch panel.
///
/// - `automatic`: Uses the built-in display. Falls back to `nil` when the lid is
///   closed (external-only setup) or the built-in display has no notch.
/// - `specific`: Uses a user-chosen screen identified by `ScreenIdentifier`.
///   Falls back to automatic if the selected screen is no longer connected.
package enum ScreenSelector: Sendable, Equatable {
    /// Automatically select the built-in display.
    case automatic

    /// A user-selected screen, persisted as a `ScreenIdentifier`.
    case specific(ScreenIdentifier)

    // MARK: Package

    /// Resolves the selector to a currently connected `NSScreen` with a notch.
    ///
    /// Returns `nil` when no suitable screen is available.
    @MainActor
    package func resolveScreen() -> NSScreen? {
        switch self {
        case .automatic:
            // Prefer the built-in display if it has a notch.
            guard let builtin = NSScreen.builtin, builtin.hasPhysicalNotch else {
                return nil
            }
            return builtin

        case let .specific(identifier):
            // Try the user-selected screen first.
            if let screen = identifier.resolve(), screen.notchSize != nil {
                return screen
            }
            // Fall back to automatic if the selected screen is gone or has no notch.
            return Self.automatic.resolveScreen()
        }
    }
}
