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

// MARK: - NotchWindowStatus

/// Snapshot emitted by the status stream to drive panel interactivity.
///
/// Carries both the open/closed flag and whether the open transition should
/// activate the app (make it key and frontmost). Notifications and boot
/// animations pass `shouldActivate = false` to avoid stealing focus.
package struct NotchWindowStatus: Sendable {
    // MARK: Lifecycle

    package init(isOpened: Bool, shouldActivate: Bool = false) {
        self.isOpened = isOpened
        self.shouldActivate = shouldActivate
    }

    // MARK: Package

    /// Whether the notch panel is open.
    package let isOpened: Bool
    /// Whether the app should activate and the panel should become key.
    package let shouldActivate: Bool
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
        panel.setFrame(geometry.notchRectInScreenCoordinates, display: false)
        panel.ignoresMouseEvents = true
        super.init(window: panel)

        panel.contentView = self.hostingView

        // Observe window resize events from NSHostingView auto-sizing so we can
        // re-center the content-sized window at the notch after each layout pass.
        self.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: panel,
            queue: .main,
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.repositionForContentSize()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        self.statusTask?.cancel()
        if let observer = self.resizeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
        self.repositionForContentSize()

        if reason.shouldActivate {
            NSApp.activate()
            panel.makeKey()
        }
    }

    /// Hides the notch panel without closing the window.
    ///
    /// The window stays on screen so the closed-state notch shape remains
    /// visible. Only ``NotchWindowControllerAdapter/tearDown()`` should
    /// remove the window entirely via `orderOut(nil)`.
    package func hide() {
        guard let panel = self.window else { return }

        self.hostingView.isInteractive = false
        self.hostingView.activeHitRect = nil
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        self.repositionForContentSize()
    }

    /// Subscribes to a status stream that drives panel interactivity and focus.
    ///
    /// The OIUI layer adapts `NotchViewModel.makeStatusStream()` into a
    /// `NotchWindowStatus` stream and passes it here. The controller toggles
    /// `ignoresMouseEvents` and `isInteractive` on each status change, and
    /// activates the app when `shouldActivate` is true.
    ///
    /// Calling this again cancels the previous subscription.
    package func subscribeToStatusStream(_ stream: AsyncStream<NotchWindowStatus>) {
        self.statusTask?.cancel()
        self.statusTask = Task { @MainActor [weak self] in
            for await status in stream {
                guard let self, !Task.isCancelled else { break }
                if status.isOpened {
                    self.hostingView.activeHitRect = nil
                    self.hostingView.isInteractive = true
                    self.window?.ignoresMouseEvents = false
                    self.window?.orderFrontRegardless()
                    self.repositionForContentSize()

                    if status.shouldActivate {
                        NSApp.activate()
                        self.window?.makeKey()
                    }
                } else {
                    self.hostingView.isInteractive = false
                    self.hostingView.activeHitRect = nil
                    self.window?.ignoresMouseEvents = true
                    self.window?.orderFrontRegardless()
                    self.repositionForContentSize()
                }
            }
        }
    }

    /// Repositions the panel for updated screen geometry.
    ///
    /// Called by `ScreenObserver` when display parameters change.
    package func updateGeometry(_ newGeometry: NotchGeometry) {
        self.geometry = newGeometry
        self.repositionForContentSize()
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

    /// Observer for window resize events triggered by NSHostingView auto-sizing.
    private var resizeObserver: (any NSObjectProtocol)?

    /// Repositions the window origin so the content-sized window is centered
    /// horizontally on the notch and pinned to the screen top.
    ///
    /// Uses `setFrameOrigin` instead of `setFrame` to avoid re-triggering
    /// the `didResizeNotification` observer.
    private func repositionForContentSize() {
        guard let panel = self.window else { return }
        let currentSize = panel.frame.size
        guard currentSize.width > 0, currentSize.height > 0 else { return }
        let targetFrame = self.geometry.panelRectInScreenCoordinates(size: currentSize)
        panel.setFrameOrigin(targetFrame.origin)
    }
}
