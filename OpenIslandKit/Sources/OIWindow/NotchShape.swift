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

    package var topCornerRadius: CGFloat
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

        path.move(to: CGPoint(x: rect.minX + tr, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + tr),
            control: CGPoint(x: rect.maxX, y: rect.minY),
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - br, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY),
        )
        path.addLine(to: CGPoint(x: rect.minX + br, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - br),
            control: CGPoint(x: rect.minX, y: rect.maxY),
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tr))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tr, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY),
        )

        path.closeSubpath()
        return path
    }
}
