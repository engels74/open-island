// @preconcurrency: CGDirectDisplayID, NSScreen predate Sendable annotations
@preconcurrency public import AppKit

// MARK: - ScreenIdentifier

/// A persistent identifier for a display, used to remember a user's screen selection.
///
/// Wraps `CGDirectDisplayID` with `Codable` support for storage in `UserDefaults`.
public struct ScreenIdentifier: Sendable, Equatable, Hashable, Codable {
    // MARK: Lifecycle

    public init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }

    public init?(screen: NSScreen) {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        self.displayID = id
    }

    // MARK: Public

    public let displayID: UInt32

    @MainActor
    public func resolve() -> NSScreen? {
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
public enum ScreenSelector: Sendable, Equatable {
    case automatic
    case specific(ScreenIdentifier)

    // MARK: Public

    @MainActor
    public func resolveScreen() -> NSScreen? {
        switch self {
        case .automatic:
            guard let builtin = NSScreen.builtin, builtin.hasPhysicalNotch else {
                return nil
            }
            return builtin

        case let .specific(identifier):
            if let screen = identifier.resolve(), screen.notchSize != nil {
                return screen
            }
            return Self.automatic.resolveScreen()
        }
    }
}
