import OIModules
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
        // Build the hit-test rect closure before creating the controller.
        let hitTestRect = Self.makeHitTestRect(viewModel: viewModel)

        self.controller = NotchWindowController(
            geometry: geometry,
            content: content,
            hitTestRect: hitTestRect,
        )

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

    /// Padding applied around the hit-test rect for comfortable interaction.
    private static let hitTestPadding: CGFloat = 10

    private let controller: NotchWindowController

    /// Builds a closure that returns the interactive rect in view-local coordinates.
    ///
    /// - Opened: rect sized to `openedSize` + padding, centered horizontally in
    ///   the full-width window, hanging from the top.
    /// - Closed/Popping: rect sized to notch width + module expansion + padding,
    ///   centered on the notch position.
    private static func makeHitTestRect(viewModel: NotchViewModel) -> @MainActor () -> CGRect {
        { [weak viewModel] in
            guard let viewModel else { return .zero }

            let geometry = viewModel.geometry
            let windowHeight = NotchGeometry.windowHeight
            let screenWidth = geometry.screenRect.width
            let notchRect = geometry.deviceNotchRect
            let padding = Self.hitTestPadding

            switch viewModel.status {
            case .opened:
                let size = viewModel.openedSize
                let rectWidth = size.width + padding * 2
                let rectHeight = size.height + padding
                let rectX = (screenWidth - rectWidth) / 2
                // Top-aligned: in AppKit view coords (bottom-left origin),
                // the top of the view is at windowHeight.
                let rectY = windowHeight - rectHeight
                return CGRect(x: rectX, y: rectY, width: rectWidth, height: rectHeight)

            case .closed,
                 .popping:
                let layout = viewModel.moduleLayout
                let margin = ModuleLayoutEngine.shapeEdgeMargin
                let closedWidth = notchRect.width + layout.totalExpansionWidth + 2 * margin + padding * 2
                let closedHeight = notchRect.height + padding
                let rectX = notchRect.midX - closedWidth / 2
                let rectY = windowHeight - closedHeight
                return CGRect(x: rectX, y: rectY, width: closedWidth, height: closedHeight)
            }
        }
    }

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
