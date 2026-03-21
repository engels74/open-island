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

    package let isOpened: Bool
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
    ///   - hitTestRect: Closure returning the current interactive rect in
    ///     view-local coordinates. Forwarded to the `PassThroughHostingView`.
    package init(
        geometry: NotchGeometry,
        content: AnyView,
        hitTestRect: @escaping @MainActor () -> CGRect = { .zero },
    ) {
        self.geometry = geometry
        self.hostingView = PassThroughHostingView(rootView: content)
        self.hasPlayedBootAnimation = false

        let panel = NotchPanel()
        panel.setFrame(geometry.windowFrame, display: false)
        panel.ignoresMouseEvents = true
        super.init(window: panel)

        self.hostingView.hitTestRect = hitTestRect
        panel.contentView = self.hostingView
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        self.statusTask?.cancel()
    }

    // MARK: Package

    package private(set) var geometry: NotchGeometry

    package func show(reason: OpenReason) {
        guard let panel = self.window else { return }

        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()

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

        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
    }

    /// Subscribes to a status stream that drives panel interactivity and focus.
    ///
    /// The OIUI layer adapts `NotchViewModel.makeStatusStream()` into a
    /// `NotchWindowStatus` stream and passes it here. The controller toggles
    /// `ignoresMouseEvents` on each status change and activates the app when
    /// `shouldActivate` is true.
    ///
    /// Calling this again cancels the previous subscription.
    package func subscribeToStatusStream(_ stream: AsyncStream<NotchWindowStatus>) {
        self.statusTask?.cancel()
        self.statusTask = Task { @MainActor [weak self] in
            for await status in stream {
                guard let self, !Task.isCancelled else { break }
                if status.isOpened {
                    self.window?.ignoresMouseEvents = false
                    self.window?.orderFrontRegardless()

                    if status.shouldActivate {
                        NSApp.activate()
                        self.window?.makeKey()
                    }
                } else {
                    self.window?.ignoresMouseEvents = true
                    self.window?.orderFrontRegardless()
                }
            }
        }
    }

    package func updateGeometry(_ newGeometry: NotchGeometry) {
        self.geometry = newGeometry
        self.window?.setFrame(newGeometry.windowFrame, display: false)
    }

    /// Briefly opens and closes the panel to teach the user where the notch is.
    package func playBootAnimationIfNeeded() {
        guard !self.hasPlayedBootAnimation else { return }
        self.hasPlayedBootAnimation = true

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }

            self.show(reason: .boot)

            try? await Task.sleep(for: .seconds(1))
            self.hide()
        }
    }

    // MARK: Private

    private let hostingView: PassThroughHostingView
    private var hasPlayedBootAnimation: Bool
    private var statusTask: Task<Void, Never>?
}
