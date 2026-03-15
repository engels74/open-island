package import Foundation
import Observation
package import OICore
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

    package init(geometry: NotchGeometry) {
        self.geometry = geometry
        self.status = .closed
        self.contentType = .instances
        self.openReason = .boot
        self.selectorUpdateToken = 0
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

    // TODO: Phase 6 — layoutEngine: ModuleLayoutEngine

    /// Token incremented when a settings-menu selector expands or collapses.
    ///
    /// Observed by SwiftUI to trigger size re-computation of the settings
    /// panel without requiring the view to know about individual selectors.
    package var selectorUpdateToken: UInt64

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
            bufferingPolicy: .bufferingNewest(1),
        )
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
