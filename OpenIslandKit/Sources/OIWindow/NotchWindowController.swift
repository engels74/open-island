@preconcurrency package import AppKit
package import SwiftUI

// MARK: - OpenReason

/// Why the notch panel is being opened. Determines focus activation behavior.
package enum OpenReason: Sendable {
    /// User clicked the notch area — activate app and make panel key.
    case click
    /// Mouse hovered over the notch — activate app and make panel key.
    case hover
    /// A notification triggered the open — do not steal focus.
    case notification
    /// First-launch animation — do not steal focus.
    case boot

    // MARK: Package

    /// Whether this reason should activate the application and make the panel key.
    package var shouldActivate: Bool {
        switch self {
        case .click,
             .hover: true
        case .notification,
             .boot: false
        }
    }
}

// MARK: - NotchWindowController

/// Manages the lifecycle of the notch panel: creation, positioning, show/hide,
/// conditional focus activation, and the first-launch boot animation.
///
/// The controller owns a `NotchPanel` (borderless, transparent, floating
/// overlay above the menu bar). It positions the panel using a
/// `NotchGeometry` value and hosts SwiftUI content through a
/// `PassThroughHostingView`.
@MainActor
package final class NotchWindowController: NSWindowController {
    // MARK: Lifecycle

    /// Creates a controller managing a notch panel for the given geometry and content.
    ///
    /// - Parameters:
    ///   - geometry: Screen geometry describing the notch position and panel frame.
    ///   - content: The SwiftUI view to host inside the panel.
    package init(geometry: NotchGeometry, content: AnyView) {
        self.geometry = geometry
        self.hostingView = PassThroughHostingView(rootView: content)
        self.hasPlayedBootAnimation = false

        let panel = NotchPanel()
        panel.setFrame(geometry.windowFrame, display: false)
        panel.ignoresMouseEvents = true
        super.init(window: panel)

        panel.contentView = self.hostingView
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Package

    /// The current screen geometry driving panel position.
    package private(set) var geometry: NotchGeometry

    /// Shows the notch panel.
    ///
    /// - Parameter reason: Why the panel is opening — determines whether the app
    ///   activates and the panel becomes key.
    package func show(reason: OpenReason) {
        guard let panel = self.window else { return }

        self.hostingView.activeHitRect = nil
        self.hostingView.isInteractive = true
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()

        if reason.shouldActivate {
            NSApp.activate()
            panel.makeKey()
        }
    }

    /// Hides the notch panel without closing the window.
    package func hide() {
        guard let panel = self.window else { return }

        self.hostingView.isInteractive = false
        self.hostingView.activeHitRect = nil
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }

    /// Subscribes to a boolean stream that drives panel interactivity.
    ///
    /// The OIUI layer adapts `NotchViewModel.makeStatusStream()` into a
    /// `Bool` stream (`true` = opened, `false` = closed) and passes it here.
    /// The controller toggles `ignoresMouseEvents` and `isInteractive` on
    /// each status change.
    ///
    /// Calling this again cancels the previous subscription.
    package func subscribeToStatusStream(_ stream: AsyncStream<Bool>) {
        self.statusTask?.cancel()
        self.statusTask = Task { @MainActor [weak self] in
            for await isOpened in stream {
                guard let self, !Task.isCancelled else { break }
                if isOpened {
                    self.hostingView.activeHitRect = nil
                    self.hostingView.isInteractive = true
                    self.window?.ignoresMouseEvents = false
                } else {
                    self.hostingView.isInteractive = false
                    self.hostingView.activeHitRect = nil
                    self.window?.ignoresMouseEvents = true
                }
            }
        }
    }

    /// Repositions the panel for updated screen geometry.
    ///
    /// Called by `ScreenObserver` when display parameters change.
    package func updateGeometry(_ newGeometry: NotchGeometry) {
        self.geometry = newGeometry
        self.window?.setFrame(newGeometry.windowFrame, display: true)
    }

    /// Plays the first-launch boot animation: briefly opens the panel, holds,
    /// then closes. Teaches the user where the notch is.
    ///
    /// Does nothing if the boot animation has already played.
    package func playBootAnimationIfNeeded() {
        guard !self.hasPlayedBootAnimation else { return }
        self.hasPlayedBootAnimation = true

        // Delay before opening.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }

            self.show(reason: .boot)

            // Hold open for 1 second, then close.
            try? await Task.sleep(for: .seconds(1))
            self.hide()
        }
    }

    // MARK: Private

    /// The hosting view that bridges SwiftUI content into the panel.
    private let hostingView: PassThroughHostingView

    /// Whether the boot animation has already played this session.
    private var hasPlayedBootAnimation: Bool

    /// Task consuming the status stream from ``subscribeToStatusStream(_:)``.
    private var statusTask: Task<Void, Never>?
}
