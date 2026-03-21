public import Foundation
public import Observation
public import OICore
public import OIModules
public import OIWindow
public import SwiftUI

// MARK: - NotchViewModel

/// Central view model managing notch state, content, and geometry.
///
/// Owns the canonical notch status and content type. The window controller
/// subscribes to status changes via ``makeStatusStream()`` to drive
/// show/hide transitions.
@Observable
@MainActor
public final class NotchViewModel {
    // MARK: Lifecycle

    /// Creates a new view model.
    ///
    /// Automatically loads any persisted module layout configuration from
    /// `UserDefaults` and reconciles it against the registry's current modules.
    public init(geometry: NotchGeometry, registry: ModuleRegistry = ModuleRegistry()) {
        self.geometry = geometry
        self.registry = registry
        self.status = .closed
        self.contentType = .instances
        self.openReason = .boot
        self.selectorUpdateToken = 0

        // Restore persisted layout so user customizations survive app restarts.
        registry.applyPersistedLayout()
    }

    // MARK: Public

    /// Current visual state of the notch panel.
    public private(set) var status: NotchStatus

    /// The content currently displayed (or to be restored on next open).
    public private(set) var contentType: NotchContentType

    /// Why the notch was most recently opened.
    public private(set) var openReason: NotchOpenReason

    /// Screen geometry driving panel position and sizing.
    public var geometry: NotchGeometry

    /// Module registry holding all registered notch modules.
    public let registry: ModuleRegistry

    /// The current module visibility context used for layout decisions.
    ///
    /// Defaults to sensible values. Updated from live `SessionStore` data
    /// via `SessionMonitor` and `NotchActivityCoordinator`.
    public var visibilityContext = ModuleVisibilityContext()

    /// Whether the mouse is hovering over the notch view (driven by SwiftUI `.onHover`).
    ///
    /// Separate from `EventMonitors.isHovering` which tracks the global event monitor.
    /// This property reflects the SwiftUI hit-test boundary and is used for visual
    /// feedback like hover shadows.
    public private(set) var isHovered = false

    /// Token incremented when a settings-menu selector expands or collapses.
    ///
    /// Observed by SwiftUI to trigger size re-computation of the settings
    /// panel without requiring the view to know about individual selectors.
    public var selectorUpdateToken: UInt64

    /// Computes the closed-state module layout from the current registry and visibility context.
    ///
    /// This is the **single source of truth** for closed-state width, consumed by both
    /// `NotchView` (visual boundary) and `PassThroughHostingView` (hit-test boundary).
    public var moduleLayout: ModuleLayoutResult {
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
    public var openedSize: CGSize {
        // Touch the token so Observation tracks it for `.menu`.
        _ = self.selectorUpdateToken

        switch self.contentType {
        case .instances:
            return CGSize(width: min(self.geometry.screenRect.width * 0.4, 480), height: 320)
        case .chat:
            return CGSize(width: min(self.geometry.screenRect.width * 0.5, 600), height: 580)
        case .menu:
            return CGSize(width: min(self.geometry.screenRect.width * 0.4, 480), height: 420)
        }
    }

    // MARK: - Status Stream

    /// Creates an `AsyncStream` that yields every ``NotchStatus`` change.
    ///
    /// **Single-consumer by convention**: calling this method again finishes
    /// the previous stream to prevent resource leaks.
    public func makeStatusStream() -> AsyncStream<NotchStatus> {
        // Finish any existing stream before creating a new one.
        self.activeStatusContinuation?.finish()

        self.statusStreamGeneration &+= 1
        let generation = self.statusStreamGeneration

        let (stream, continuation) = AsyncStream<NotchStatus>.makeStream(
            // State snapshot — only the latest status matters.
            bufferingPolicy: .bufferingNewest(1),
        )

        continuation.onTermination = { [weak self] _ in
            // Clear the stored continuation so the adapter doesn't yield
            // into a terminated stream. Guard against a stale termination
            // handler (from a previously-finished stream) wiping a newer
            // continuation — only clear if the generation still matches.
            Task { @MainActor in
                guard let self, self.statusStreamGeneration == generation else { return }
                self.activeStatusContinuation = nil
            }
        }

        self.activeStatusContinuation = continuation

        // Emit the current status immediately so the subscriber sees the
        // initial state without waiting for the next mutation. This ensures
        // the window controller sets the correct `ignoresMouseEvents` value
        // even when no subsequent status change occurs (e.g. boot animation
        // already played).
        continuation.yield(self.status)

        return stream
    }

    /// Opens the notch panel for the given reason.
    ///
    /// Sets ``status`` to `.opened` and yields to the status stream.
    public func notchOpen(reason: NotchOpenReason) {
        self.openReason = reason
        self.status = .opened
        self.activeStatusContinuation?.yield(.opened)
    }

    /// Closes the notch panel.
    ///
    /// Preserves the current ``contentType`` so the user returns to
    /// the same view on the next open.
    public func notchClose() {
        // contentType is intentionally NOT reset — state preservation.
        self.status = .closed
        self.activeStatusContinuation?.yield(.closed)
    }

    /// Switches the panel's content to a new type.
    ///
    /// Can be called while opened or closed. When closed, this sets the
    /// content that will be shown on the next open.
    public func switchContent(_ newContent: NotchContentType) {
        self.contentType = newContent
    }

    /// Increments the selector update token, causing ``openedSize`` to
    /// be re-evaluated by any observing views.
    public func invalidateMenuLayout() {
        self.selectorUpdateToken &+= 1
    }

    /// Plays a brief "pop" animation by transitioning through the `.popping`
    /// status. Used on first launch to teach the user where the notch lives.
    ///
    /// Sets status to `.popping`, waits briefly, then returns to `.closed`.
    /// Does nothing if a boot animation has already played this session.
    public func performBootAnimation() {
        guard !self.hasPlayedBootAnimation else { return }
        self.hasPlayedBootAnimation = true

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self else { return }

            self.status = .popping
            self.activeStatusContinuation?.yield(.popping)

            try? await Task.sleep(for: .seconds(1))

            // Only close if still in the popping state — the user or
            // activity coordinator may have opened the notch during the animation.
            guard self.status == .popping else { return }
            self.status = .closed
            self.activeStatusContinuation?.yield(.closed)
        }
    }

    /// Updates the hover state from SwiftUI's `.onHover` modifier.
    public func setHovered(_ hovered: Bool) {
        self.isHovered = hovered
    }

    // MARK: Package

    /// Accent color for the mascot, tracked by Observation so views
    /// using this value re-render when the color changes in settings.
    ///
    /// Initialized from `AppSettings.mascotColor` and kept in sync by
    /// `SettingsMenuView` when the user picks a new color.
    package var mascotColor: Color = AppSettings.mascotColor

    // MARK: Private

    /// Whether the boot animation has already played this session.
    @ObservationIgnored private var hasPlayedBootAnimation = false

    /// The continuation for the current status stream (if any).
    @ObservationIgnored private var activeStatusContinuation: AsyncStream<NotchStatus>.Continuation?

    /// Generation counter incremented each time ``makeStatusStream()`` creates
    /// a new continuation. Used by `onTermination` to avoid clearing a
    /// successor's continuation.
    @ObservationIgnored private var statusStreamGeneration: UInt64 = 0
}
