package import Foundation
import Observation
package import OICore
package import OIModules
package import OIWindow

// MARK: - NotchViewModel

/// Central view model managing notch state, content, and geometry.
///
/// Owns the canonical notch status and content type. The window controller
/// subscribes to status changes via ``makeStatusStream()`` to drive
/// show/hide transitions.
@Observable
@MainActor
package final class NotchViewModel {
    // MARK: Lifecycle

    /// Creates a new view model.
    ///
    /// Automatically loads any persisted module layout configuration from
    /// `UserDefaults` and reconciles it against the registry's current modules.
    package init(geometry: NotchGeometry, registry: ModuleRegistry = ModuleRegistry()) {
        self.geometry = geometry
        self.registry = registry
        self.status = .closed
        self.contentType = .instances
        self.openReason = .boot
        self.selectorUpdateToken = 0

        // Restore persisted layout so user customizations survive app restarts.
        registry.applyPersistedLayout()
    }

    // MARK: Package

    /// Current visual state of the notch panel.
    package private(set) var status: NotchStatus

    /// The content currently displayed (or to be restored on next open).
    package private(set) var contentType: NotchContentType

    /// Why the notch was most recently opened.
    package private(set) var openReason: NotchOpenReason

    /// Screen geometry driving panel position and sizing.
    package var geometry: NotchGeometry

    /// Module registry holding all registered notch modules.
    package let registry: ModuleRegistry

    /// The current module visibility context used for layout decisions.
    ///
    /// Defaults to sensible values. The integration layer will update this
    /// from live `SessionStore` data in a later phase.
    package var visibilityContext = ModuleVisibilityContext()

    /// Token incremented when a settings-menu selector expands or collapses.
    ///
    /// Observed by SwiftUI to trigger size re-computation of the settings
    /// panel without requiring the view to know about individual selectors.
    package var selectorUpdateToken: UInt64

    /// Computes the closed-state module layout from the current registry and visibility context.
    ///
    /// This is the **single source of truth** for closed-state width, consumed by both
    /// `NotchView` (visual boundary) and `PassThroughHostingView` (hit-test boundary).
    package var moduleLayout: ModuleLayoutResult {
        ModuleLayoutEngine.layout(
            modules: self.registry.allModules,
            context: self.visibilityContext,
            config: self.registry.layoutConfig,
        )
    }

    /// The preferred panel size when the notch is opened.
    ///
    /// Varies by content type. For `.menu`, the token dependency ensures
    /// the size is recomputed whenever a selector expands/collapses.
    package var openedSize: CGSize {
        // Touch the token so Observation tracks it for `.menu`.
        _ = self.selectorUpdateToken

        switch self.contentType {
        case .instances:
            return CGSize(width: 720, height: 480)
        case .chat:
            return CGSize(width: 720, height: 580)
        case .menu:
            return CGSize(width: 420, height: 380)
        }
    }

    // MARK: - Status Stream

    /// Creates an `AsyncStream` that yields every ``NotchStatus`` change.
    ///
    /// **Single-consumer by convention**: calling this method again finishes
    /// the previous stream to prevent resource leaks.
    package func makeStatusStream() -> AsyncStream<NotchStatus> {
        // Finish any existing stream before creating a new one.
        self.activeStatusContinuation?.finish()

        let (stream, continuation) = AsyncStream<NotchStatus>.makeStream(
            // State snapshot — only the latest status matters.
            bufferingPolicy: .bufferingNewest(1),
        )

        continuation.onTermination = { [weak self] _ in
            // Clear the stored continuation so the adapter doesn't yield
            // into a terminated stream. MainActor access is safe here
            // because NotchViewModel is @Observable on MainActor.
            Task { @MainActor in
                self?.activeStatusContinuation = nil
            }
        }

        self.activeStatusContinuation = continuation
        return stream
    }

    /// Opens the notch panel for the given reason.
    ///
    /// Sets ``status`` to `.opened` and yields to the status stream.
    package func notchOpen(reason: NotchOpenReason) {
        self.openReason = reason
        self.status = .opened
        self.activeStatusContinuation?.yield(.opened)
    }

    /// Closes the notch panel.
    ///
    /// Preserves the current ``contentType`` so the user returns to
    /// the same view on the next open.
    package func notchClose() {
        // contentType is intentionally NOT reset — state preservation.
        self.status = .closed
        self.activeStatusContinuation?.yield(.closed)
    }

    /// Switches the panel's content to a new type.
    ///
    /// Can be called while opened or closed. When closed, this sets the
    /// content that will be shown on the next open.
    package func switchContent(_ newContent: NotchContentType) {
        self.contentType = newContent
    }

    /// Increments the selector update token, causing ``openedSize`` to
    /// be re-evaluated by any observing views.
    package func invalidateMenuLayout() {
        self.selectorUpdateToken &+= 1
    }

    // MARK: Private

    /// The continuation for the current status stream (if any).
    @ObservationIgnored private var activeStatusContinuation: AsyncStream<NotchStatus>.Continuation?
}
