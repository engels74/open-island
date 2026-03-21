@preconcurrency public import AppKit

// MARK: - NotchGeometry

/// All coordinates use AppKit's bottom-left origin convention.
public struct NotchGeometry: Sendable, Equatable {
    // MARK: Lifecycle

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

    public static let windowHeight: CGFloat = 620

    public let deviceNotchRect: CGRect
    public let screenRect: CGRect

    // MARK: - Derived Geometry

    public var paddedNotchRect: CGRect {
        self.deviceNotchRect.insetBy(
            dx: -Self.horizontalPadding,
            dy: -Self.verticalPadding,
        )
    }

    public var notchRectInScreenCoordinates: CGRect {
        CGRect(
            x: self.deviceNotchRect.origin.x + self.screenRect.origin.x,
            y: self.deviceNotchRect.origin.y + self.screenRect.origin.y,
            width: self.deviceNotchRect.width,
            height: self.deviceNotchRect.height,
        )
    }

    // MARK: - Window Frame

    public var windowFrame: CGRect {
        CGRect(
            x: self.screenRect.origin.x,
            y: self.screenRect.maxY - Self.windowHeight,
            width: self.screenRect.width,
            height: Self.windowHeight,
        )
    }

    // MARK: - Hit Testing

    public func isPointInNotch(_ point: CGPoint) -> Bool {
        self.paddedNotchRect.contains(point)
    }

    public func isPointInsidePanel(_ point: CGPoint, size: CGSize) -> Bool {
        let panelRect = self.panelRectLocal(size: size)
        return panelRect.contains(point)
    }

    /// Used for click-outside dismissal.
    public func isPointOutsidePanel(_ point: CGPoint, size: CGSize) -> Bool {
        !self.isPointInsidePanel(point, size: size)
    }

    // MARK: Private

    // MARK: Padding Constants

    private static let horizontalPadding: CGFloat = 10
    private static let verticalPadding: CGFloat = 5

    private func panelRectLocal(size: CGSize) -> CGRect {
        let panelX = self.deviceNotchRect.midX - size.width / 2
        let panelY = self.screenRect.height - size.height
        return CGRect(x: panelX, y: panelY, width: size.width, height: size.height)
    }
}
