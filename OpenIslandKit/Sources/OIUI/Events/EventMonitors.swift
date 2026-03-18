@preconcurrency public import AppKit
public import OIWindow

// MARK: - EventMonitors

/// Coordinates multiple `EventMonitor` instances for notch interaction detection.
///
/// Manages hover detection (with throttling), click-outside dismissal, keyboard
/// shortcuts, and mouse drag tracking. The coordinator owns individual monitors
/// and exposes `startAll()` / `stopAll()` for lifecycle management.
@MainActor
public final class EventMonitors {
    // MARK: Lifecycle

    /// Creates the event monitor coordinator.
    ///
    /// - Parameters:
    ///   - onHoverEnter: Called when the mouse enters the notch area.
    ///   - onHoverExit: Called when the mouse leaves the notch area.
    ///   - onClickOutside: Called with the triggering event when a click occurs outside the panel area.
    ///   - onKeyboardShortcut: Called when the keyboard shortcut is triggered.
    ///   - onDrag: Called with mouse position during drag interactions.
    public init(
        onHoverEnter: @escaping () -> Void,
        onHoverExit: @escaping () -> Void,
        onClickOutside: @escaping (NSEvent) -> Void,
        onKeyboardShortcut: @escaping () -> Void,
        onDrag: @escaping (CGPoint) -> Void,
    ) {
        self.onHoverEnter = onHoverEnter
        self.onHoverExit = onHoverExit
        self.onClickOutside = onClickOutside
        self.onKeyboardShortcut = onKeyboardShortcut
        self.onDrag = onDrag
    }

    // MARK: Public

    /// The current notch geometry for hit testing. Update when geometry changes.
    public var geometry: NotchGeometry?

    /// The opened panel size for click-outside detection. Set to `nil` when closed.
    public var panelSize: CGSize?

    /// Whether the mouse is currently hovering over the notch area.
    public private(set) var isHovering = false

    /// The keyboard shortcut modifier flags. Defaults to Option.
    public var shortcutModifiers: NSEvent.ModifierFlags = .option

    /// The keyboard shortcut key code. Defaults to "n" (key code 45).
    public var shortcutKeyCode: UInt16 = 45

    /// Installs all event monitors.
    public func startAll() {
        guard !self.isRunning else { return }
        self.isRunning = true
        self.buildMonitors()
        for monitor in self.monitors {
            monitor.start()
        }
    }

    /// Removes all event monitors and resets hover state.
    public func stopAll() {
        guard self.isRunning else { return }
        self.isRunning = false
        for monitor in self.monitors {
            monitor.stop()
        }
        self.monitors.removeAll()
        self.hoverDelayTask?.cancel()
        self.hoverDelayTask = nil
        self.isHovering = false
    }

    // MARK: Private

    /// Minimum interval between throttled mouse-move handler invocations (~50ms).
    private static let throttleInterval: UInt64 = 50_000_000

    /// Delay before hover triggers an open (~1 second), matching Claude Island behavior.
    private static let hoverDelay: Duration = .seconds(1)

    private var monitors: [EventMonitor] = []
    private var isRunning = false
    private var lastMoveTimestamp: UInt64 = 0
    private var hoverDelayTask: Task<Void, Never>?

    private let onHoverEnter: () -> Void
    private let onHoverExit: () -> Void
    private let onClickOutside: (NSEvent) -> Void
    private let onKeyboardShortcut: () -> Void
    private let onDrag: (CGPoint) -> Void

    private func buildMonitors() {
        self.monitors = [
            self.makeMouseMoveMonitor(),
            self.makeClickOutsideMonitor(),
            self.makeKeyboardMonitor(),
            self.makeDragMonitor(),
        ]
    }

    // MARK: - Mouse Movement (Hover Detection)

    /// Creates a throttled mouse-move monitor for hover enter/exit detection.
    ///
    /// Uses `DispatchTime` comparison to throttle callbacks to ~20 events/second.
    /// Global scope captures mouse movement outside the app's windows.
    private func makeMouseMoveMonitor() -> EventMonitor {
        EventMonitor(mask: .mouseMoved, scope: .global) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseMove()
            }
            return event
        }
    }

    private func handleMouseMove() {
        // Throttle: skip if less than ~50ms since last handled event.
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - self.lastMoveTimestamp >= Self.throttleInterval else { return }
        self.lastMoveTimestamp = now

        guard let geometry else { return }

        // Convert global mouse location to screen-local coordinates.
        let globalPoint = NSEvent.mouseLocation
        let localPoint = CGPoint(
            x: globalPoint.x - geometry.screenRect.origin.x,
            y: globalPoint.y - geometry.screenRect.origin.y,
        )

        let inNotch = geometry.isPointInNotch(localPoint)

        if inNotch, !self.isHovering {
            // Mark hovering immediately so exit detection works,
            // but delay the actual open callback by ~1 second.
            self.isHovering = true
            self.hoverDelayTask?.cancel()
            self.hoverDelayTask = Task { [onHoverEnter] in
                try? await Task.sleep(for: Self.hoverDelay)
                guard !Task.isCancelled else { return }
                onHoverEnter()
            }
        } else if !inNotch, self.isHovering {
            // Only exit hover if also outside panel (when open).
            if let panelSize, geometry.isPointInsidePanel(localPoint, size: panelSize) {
                return
            }
            // Cancel pending open if mouse exits before delay expires.
            self.hoverDelayTask?.cancel()
            self.hoverDelayTask = nil
            self.isHovering = false
            self.onHoverExit()
        }
    }

    // MARK: - Click-Outside Detection

    /// Creates a monitor detecting clicks outside the opened panel area.
    ///
    /// Uses both global (clicks outside the app) and local (clicks inside the app
    /// but outside the panel) scopes.
    private func makeClickOutsideMonitor() -> EventMonitor {
        EventMonitor(
            mask: [.leftMouseDown, .rightMouseDown],
            scope: .both,
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleClick(event)
            }
            return event
        }
    }

    private func handleClick(_ event: NSEvent) {
        guard let geometry, let panelSize else { return }

        let globalPoint = NSEvent.mouseLocation
        let localPoint = CGPoint(
            x: globalPoint.x - geometry.screenRect.origin.x,
            y: globalPoint.y - geometry.screenRect.origin.y,
        )

        if geometry.isPointOutsidePanel(localPoint, size: panelSize) {
            self.onClickOutside(event)
        }
    }

    // MARK: - Keyboard Shortcut

    /// Creates a global key-down monitor for the configurable keyboard shortcut.
    private func makeKeyboardMonitor() -> EventMonitor {
        EventMonitor(mask: .keyDown, scope: .global) { [weak self] event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let keyCode = event.keyCode
            MainActor.assumeIsolated {
                self?.handleKeyDown(modifiers: modifiers, keyCode: keyCode)
            }
            return event
        }
    }

    private func handleKeyDown(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        guard modifiers == self.shortcutModifiers,
              keyCode == self.shortcutKeyCode
        else { return }

        self.onKeyboardShortcut()
    }

    // MARK: - Mouse Drag Tracking

    /// Creates monitors for left-mouse-dragged events within the application.
    ///
    /// Uses local scope since drags within the panel are app-local events.
    private func makeDragMonitor() -> EventMonitor {
        EventMonitor(mask: .leftMouseDragged, scope: .local) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let location = NSEvent.mouseLocation
                self.onDrag(location)
            }
            return event
        }
    }
}
