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
    ///   - viewModel: Provides the ``NotchStatus`` stream mapped to `Bool`.
    public init(geometry: NotchGeometry, content: AnyView, viewModel: NotchViewModel) {
        self.controller = NotchWindowController(geometry: geometry, content: content)

        // Map NotchStatus → Bool: opened/popping = true, closed = false.
        let statusStream = viewModel.makeStatusStream()
        let boolStream = AsyncStream<Bool> { continuation in
            let task = Task { @MainActor in
                for await status in statusStream {
                    let isOpened = switch status {
                    case .opened,
                         .popping: true
                    case .closed: false
                    }
                    continuation.yield(isOpened)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }

        self.controller.subscribeToStatusStream(boolStream)
        self.controller.show(reason: .boot)
        self.controller.playBootAnimationIfNeeded()
    }

    // MARK: Public

    // MARK: - WindowControllerHandle

    public func updateGeometry(_ geometry: NotchGeometry) {
        self.controller.updateGeometry(geometry)
    }

    public func tearDown() {
        self.controller.hide()
        self.controller.window?.close()
    }

    // MARK: Private

    private let controller: NotchWindowController
}
