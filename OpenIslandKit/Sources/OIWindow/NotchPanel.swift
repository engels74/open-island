// @preconcurrency: NSPanel, NSWindow predate Sendable annotations
@preconcurrency package import AppKit

// MARK: - NotchPanel

/// Borderless, non-activating, transparent floating panel for the notch overlay.
///
/// Sits above the menu bar (`statusBar + 1`) and spans all Spaces.
/// Mouse clicks that miss the SwiftUI content are re-posted as `CGEvent`s
/// so they reach the menu bar or the window underneath.
package final class NotchPanel: NSPanel {
    // MARK: Lifecycle

    package init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true,
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.becomesKeyOnlyIfNeeded = true
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
    }

    // MARK: Package

    override package var canBecomeKey: Bool {
        true
    }

    override package func sendEvent(_ event: NSEvent) {
        if Self.repostableMouseTypes.contains(event.type) {
            let windowPoint = event.locationInWindow
            if contentView?.hitTest(windowPoint) == nil {
                self.repostMouseEvent(event)
                return
            }
        }
        super.sendEvent(event)
    }

    // MARK: Private

    private static let repostableMouseTypes: Set<NSEvent.EventType> = [
        .leftMouseDown, .leftMouseUp,
        .rightMouseDown, .rightMouseUp,
    ]

    /// Re-posts a mouse event as a `CGEvent` so it reaches whatever is behind this panel.
    ///
    /// AppKit uses bottom-left origin; CoreGraphics uses top-left origin.
    /// The conversion flips Y relative to the main screen's height.
    private func repostMouseEvent(_ event: NSEvent) {
        guard let screen = self.screen ?? NSScreen.main else { return }

        // Convert window-local point → global screen coordinates (AppKit, bottom-left origin).
        let screenPoint = self.convertPoint(toScreen: event.locationInWindow)

        // Flip Y for CoreGraphics (top-left origin).
        let mainScreenHeight = screen.frame.height + screen.frame.origin.y
        let cgPoint = CGPoint(x: screenPoint.x, y: mainScreenHeight - screenPoint.y)

        let cgEventType: CGEventType
        switch event.type {
        case .leftMouseDown: cgEventType = .leftMouseDown
        case .leftMouseUp: cgEventType = .leftMouseUp
        case .rightMouseDown: cgEventType = .rightMouseDown
        case .rightMouseUp: cgEventType = .rightMouseUp
        default: return
        }

        guard let cgEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: cgEventType,
            mouseCursorPosition: cgPoint,
            mouseButton: event.type == .rightMouseDown || event.type == .rightMouseUp
                ? .right : .left,
        )
        else { return }

        self.ignoresMouseEvents = true
        cgEvent.post(tap: .cghidEventTap)

        // Re-enable mouse events on the next run loop cycle so subsequent
        // events (hover, future clicks) are still received by this panel.
        DispatchQueue.main.async { [weak self] in
            self?.ignoresMouseEvents = false
        }
    }
}
