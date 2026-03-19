@preconcurrency package import AppKit
package import SwiftUI

// MARK: - PassThroughHostingView

/// An `NSHostingView` subclass that conditionally passes mouse events through to
/// the window or desktop behind it.
///
/// Hit testing is governed by a `hitTestRect` closure that returns the current
/// interactive region in view-local coordinates. Points outside this rect fall
/// through to the menu bar or other windows. The closure is set by
/// `NotchWindowControllerAdapter` and dynamically returns a panel-sized rect
/// (opened) or notch-sized rect (closed/popping).
///
/// This works in concert with `NotchPanel`'s `sendEvent(_:)` re-posting: when the
/// hit-test rect excludes a point, the panel sees no hit target and re-posts the
/// event; otherwise, hits are handled by the SwiftUI content.
@MainActor
package final class PassThroughHostingView: NSHostingView<AnyView> {
    // MARK: Lifecycle

    package required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Package

    /// Closure returning the current interactive rect in view-local coordinates.
    ///
    /// Points inside this rect receive normal `NSHostingView` hit testing;
    /// points outside return `nil` (pass-through). Defaults to `.zero`,
    /// meaning all events pass through until a rect is configured.
    package var hitTestRect: @MainActor () -> CGRect = { .zero }

    // MARK: - Hit Testing

    override package func hitTest(_ point: NSPoint) -> NSView? {
        guard self.hitTestRect().contains(point) else { return nil }
        return super.hitTest(point)
    }
}
