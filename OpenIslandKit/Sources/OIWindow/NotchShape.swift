package import SwiftUI

/// A SwiftUI `Shape` that draws the silhouette of a MacBook notch.
///
/// The path consists of:
/// - A flat top edge spanning the width (inset by the top corner radius).
/// - Quadratic Bézier shoulders rounding from the top edge down to the sides.
/// - Straight vertical sides.
/// - Quadratic Bézier curves rounding the bottom corners.
///
/// Both `topCornerRadius` and `bottomCornerRadius` are animatable, enabling
/// smooth transitions between closed (small radii) and opened (larger radii) states.
package struct NotchShape: Shape {
    // MARK: Lifecycle

    package init(topCornerRadius: CGFloat = 6, bottomCornerRadius: CGFloat = 14) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    // MARK: Package

    /// Radius applied to the top-left and top-right shoulder curves.
    package var topCornerRadius: CGFloat

    /// Radius applied to the bottom-left and bottom-right corners.
    package var bottomCornerRadius: CGFloat

    package var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(self.topCornerRadius, self.bottomCornerRadius) }
        set {
            self.topCornerRadius = newValue.first
            self.bottomCornerRadius = newValue.second
        }
    }

    package func path(in rect: CGRect) -> Path {
        let halfWidth = rect.width / 2
        let halfHeight = rect.height / 2

        // Clamp radii so they never exceed half the available dimension.
        let tr = min(self.topCornerRadius, halfWidth, halfHeight)
        let br = min(self.bottomCornerRadius, halfWidth, halfHeight)

        var path = Path()

        // Start at the top-left shoulder tangent point.
        path.move(to: CGPoint(x: rect.minX + tr, y: rect.minY))

        // Flat top edge → top-right shoulder tangent point.
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))

        // Top-right shoulder: quadratic Bézier from top edge to right side.
        // Control point at the geometric corner pulls the curve outward.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + tr),
            control: CGPoint(x: rect.maxX, y: rect.minY),
        )

        // Right side straight down to the bottom-right curve start.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))

        // Bottom-right corner: curve from right side inward along the bottom.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - br, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY),
        )

        // Flat bottom edge → bottom-left curve start.
        path.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))

        // Bottom-left corner: curve from bottom edge up along the left side.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - br),
            control: CGPoint(x: rect.minX, y: rect.maxY),
        )

        // Left side straight up to the top-left shoulder curve start.
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tr))

        // Top-left shoulder: curve from left side back to the top edge.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tr, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY),
        )

        path.closeSubpath()
        return path
    }
}
