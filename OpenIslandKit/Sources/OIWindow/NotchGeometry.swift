@preconcurrency public import AppKit

// MARK: - NotchGeometry

/// Pure value type capturing the geometry of a notch-display screen.
///
/// All coordinates use AppKit's bottom-left origin convention.
/// The struct is fully `Sendable` — no mutable state, no reference types.
public struct NotchGeometry: Sendable, Equatable {
    // MARK: Lifecycle

    /// Creates geometry from a notch size and the screen it belongs to.
    ///
    /// - Parameters:
    ///   - notchSize: The physical notch dimensions (width × height).
    ///   - screenFrame: The screen's frame in global coordinates.
    public init(notchSize: CGSize, screenFrame: CGRect) {
        self.screenRect = screenFrame

        // The notch is centered horizontally at the top of the screen.
        // In AppKit coordinates (bottom-left origin), "top" = maxY.
        let notchX = screenFrame.midX - notchSize.width / 2 - screenFrame.origin.x
        let notchY = screenFrame.height - notchSize.height
        self.deviceNotchRect = CGRect(
            x: notchX,
            y: notchY,
            width: notchSize.width,
            height: notchSize.height,
        )
    }

    // MARK: Public

    /// Fixed panel height when the notch is opened.
    public static let windowHeight: CGFloat = 750

    /// The hardware notch rect in screen-local coordinates (origin = bottom-left of screen).
    public let deviceNotchRect: CGRect

    /// The full screen frame in global (multi-display) coordinates.
    public let screenRect: CGRect

    // MARK: - Derived Geometry

    /// The notch rect with hit-test padding applied (screen-local coordinates).
    public var paddedNotchRect: CGRect {
        self.deviceNotchRect.insetBy(
            dx: -Self.horizontalPadding,
            dy: -Self.verticalPadding,
        )
    }

    /// The notch rect in global (multi-display) screen coordinates.
    public var notchRectInScreenCoordinates: CGRect {
        CGRect(
            x: self.deviceNotchRect.origin.x + self.screenRect.origin.x,
            y: self.deviceNotchRect.origin.y + self.screenRect.origin.y,
            width: self.deviceNotchRect.width,
            height: self.deviceNotchRect.height,
        )
    }

    // MARK: - Window Frame

    /// The window frame for the notch panel in global screen coordinates.
    ///
    /// The window spans the full screen width and uses the fixed `windowHeight`,
    /// positioned at the top of the screen.
    public var windowFrame: CGRect {
        CGRect(
            x: self.screenRect.origin.x,
            y: self.screenRect.maxY - Self.windowHeight,
            width: self.screenRect.width,
            height: Self.windowHeight,
        )
    }

    /// The opened panel rect in global screen coordinates, given a panel size.
    ///
    /// The panel hangs down from the notch, centered on the notch's horizontal center.
    public func panelRectInScreenCoordinates(size: CGSize) -> CGRect {
        let panelX = self.notchRectInScreenCoordinates.midX - size.width / 2
        // Panel top aligns with screen top (maxY), extends downward.
        let panelY = self.screenRect.maxY - size.height
        return CGRect(x: panelX, y: panelY, width: size.width, height: size.height)
    }

    // MARK: - Hit Testing

    /// Whether the point falls within the padded notch area (screen-local coordinates).
    ///
    /// Uses ±10px horizontal and ±5px vertical padding around the hardware notch rect.
    public func isPointInNotch(_ point: CGPoint) -> Bool {
        self.paddedNotchRect.contains(point)
    }

    /// Whether the point is inside the opened panel bounds (screen-local coordinates).
    public func isPointInsidePanel(_ point: CGPoint, size: CGSize) -> Bool {
        let panelRect = self.panelRectLocal(size: size)
        return panelRect.contains(point)
    }

    /// Whether the point is outside the opened panel bounds (screen-local coordinates).
    ///
    /// Used for click-outside dismissal.
    public func isPointOutsidePanel(_ point: CGPoint, size: CGSize) -> Bool {
        !self.isPointInsidePanel(point, size: size)
    }

    // MARK: Private

    // MARK: Padding Constants

    /// Horizontal hit-test padding around the notch (±10px each side).
    private static let horizontalPadding: CGFloat = 10

    /// Vertical hit-test padding below the notch (±5px).
    private static let verticalPadding: CGFloat = 5

    /// The panel rect in screen-local coordinates (origin relative to screen bottom-left).
    private func panelRectLocal(size: CGSize) -> CGRect {
        let panelX = self.deviceNotchRect.midX - size.width / 2
        let panelY = self.screenRect.height - size.height
        return CGRect(x: panelX, y: panelY, width: size.width, height: size.height)
    }
}
