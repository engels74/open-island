public import OIWindow
public import SwiftUI

// MARK: - NotchWindowControllerAdapter

/// Bridges ``NotchWindowController`` to the ``WindowControllerHandle`` protocol.
///
/// `WindowManager` (OIWindow) cannot import OIUI, so it operates on opaque
/// `WindowControllerHandle` values. This adapter wraps a real
/// `NotchWindowController`, maps the view model's `NotchStatus` stream into
/// the `Bool` stream the controller expects, and triggers the boot animation.
@MainActor
public final class NotchWindowControllerAdapter: WindowControllerHandle {
    // MARK: Lifecycle

    /// Creates an adapter that owns a new ``NotchWindowController``.
    ///
    /// - Parameters:
    ///   - geometry: Initial screen geometry for the notch panel.
    ///   - content: The SwiftUI root view hosted inside the panel.
    ///   - viewModel: Provides the ``NotchStatus`` stream mapped to ``NotchWindowStatus``.
    public init(geometry: NotchGeometry, content: AnyView, viewModel: NotchViewModel) {
        self.controller = NotchWindowController(geometry: geometry, content: content)

        // Map NotchStatus → NotchWindowStatus with activation info from openReason.
        let statusStream = viewModel.makeStatusStream()
        let windowStatusStream = AsyncStream<NotchWindowStatus> { continuation in
            let task = Task { @MainActor in
                for await status in statusStream {
                    let isOpened = switch status {
                    case .opened,
                         .popping: true
                    case .closed: false
                    }
                    // Only activate app for interactive opens (click/hover),
                    // not for notifications, permission requests, or boot.
                    let shouldActivate = isOpened && Self.shouldActivate(for: viewModel.openReason)
                    continuation.yield(NotchWindowStatus(isOpened: isOpened, shouldActivate: shouldActivate))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        self.controller.subscribeToStatusStream(windowStatusStream)
        self.controller.show(reason: .boot)

        // Boot animation driven through view model status (.popping → .closed)
        // instead of directly calling show/hide on the window controller.
        viewModel.performBootAnimation()
    }

    // MARK: Public

    // MARK: - WindowControllerHandle

    public func updateGeometry(_ geometry: NotchGeometry) {
        self.controller.updateGeometry(geometry)
    }

    public func tearDown() {
        self.controller.hide()
        self.controller.window?.orderOut(nil)
        self.controller.window?.close()
    }

    // MARK: Private

    private let controller: NotchWindowController

    /// Whether the given open reason should activate the app and make the panel key.
    ///
    /// Interactive opens (click, hover) activate so the app receives keyboard
    /// events like Cmd+Q. Automatic opens (notification, permission, boot)
    /// do not activate to avoid stealing focus from the user's current app.
    private static func shouldActivate(for reason: NotchOpenReason) -> Bool {
        switch reason {
        case .click,
             .hover: true
        case .notification,
             .permissionRequest,
             .boot: false
        }
    }
}
