@preconcurrency package import AppKit
package import SwiftUI

// MARK: - PassThroughHostingView

// MARK: Hit-test / visual sync contract

//
// The closed-state notch width is computed by `ModuleLayoutEngine` in OIModules.
// `ModuleLayoutEngine.layout(modules:context:)` returns a `ModuleLayoutResult`
// whose `totalExpansionWidth` determines how far the notch extends beyond the
// device notch rect. This view's `activeHitRect` must be derived from that same
// result so that the AppKit hit-test boundary matches the SwiftUI visual boundary
// rendered by `NotchView` (OIUI). Never compute closed-state width independently.
//
// Counterpart: see the matching contract comment in `NotchView.swift` (OIUI).

/// An `NSHostingView` subclass that conditionally passes mouse events through to
/// the window or desktop behind it.
///
/// When `isInteractive` is `false` (the "closed" state), `hitTest(_:)` returns `nil`
/// for all points, letting clicks fall through to the menu bar or other windows.
/// When `isInteractive` is `true` (the "opened" state), `hitTest(_:)` uses the
/// default `NSHostingView` behavior so SwiftUI content receives events normally.
///
/// This works in concert with `NotchPanel`'s `sendEvent(_:)` re-posting: when closed,
/// the panel sees no hit target and re-posts the event; when opened, hits are handled
/// by the SwiftUI content.
@MainActor
package final class PassThroughHostingView: NSHostingView<AnyView> {
    // MARK: Lifecycle

    package required init(rootView: AnyView) {
        self.isInteractive = false
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Package

    /// Controls whether the view accepts mouse events.
    ///
    /// - `false`: all hit tests return `nil` (pass-through to menu bar).
    /// - `true`: default `NSHostingView` hit testing (SwiftUI content is interactive).
    package var isInteractive: Bool

    /// Optional rect limiting where hit tests succeed when `isInteractive` is `true`.
    ///
    /// When set, `hitTest(_:)` returns `nil` for points outside this rect even if
    /// `isInteractive` is `true`. This enables a "partially interactive" mode where
    /// only a subregion (e.g. the notch area) accepts hits while the rest passes
    /// through. Has no effect when `isInteractive` is `false` (all hits pass through
    /// regardless).
    ///
    /// When `nil`, the full view area is interactive (the default for the opened state).
    package var activeHitRect: CGRect?

    // MARK: - Hit Testing

    override package func hitTest(_ point: NSPoint) -> NSView? {
        guard self.isInteractive else { return nil }
        if let rect = self.activeHitRect, !rect.contains(point) {
            return nil
        }
        return super.hitTest(point)
    }
}
