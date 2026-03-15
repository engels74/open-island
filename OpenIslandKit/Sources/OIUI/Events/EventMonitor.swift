@preconcurrency package import AppKit
import Synchronization

// MARK: - EventMonitorTokens

/// Monitor tokens protected by `Mutex` for safe access from `deinit`.
///
/// Uses `@unchecked Sendable` because the contained `Any?` monitor tokens
/// are only accessed under the lock.
private struct EventMonitorTokens: @unchecked Sendable {
    var global: Any?
    var local: Any?
}

// MARK: - EventMonitor

/// Reusable wrapper around `NSEvent` global and local event monitors.
///
/// Encapsulates the start/stop lifecycle of `NSEvent.addGlobalMonitorForEvents`
/// and `NSEvent.addLocalMonitorForEvents`. Monitors are removed on `stop()` and
/// in `deinit` to prevent leaks.
///
/// - Important: All callbacks fire on the main thread. Create and manage
///   `EventMonitor` instances from `@MainActor`-isolated code.
@MainActor
package final class EventMonitor {
    // MARK: Lifecycle

    /// Creates an event monitor for the specified event mask.
    ///
    /// - Parameters:
    ///   - mask: The event types to monitor.
    ///   - scope: Whether to install global, local, or both monitors.
    ///   - handler: Called on each matching event on the main thread.
    ///     For local monitors, return the event to pass it through or `nil` to consume it.
    package init(
        mask: NSEvent.EventTypeMask,
        scope: MonitorScope = .global,
        handler: @escaping @Sendable (NSEvent) -> NSEvent?,
    ) {
        self.mask = mask
        self.scope = scope
        self._handler = handler
    }

    deinit {
        _monitors.withLock { tokens in
            if let monitor = tokens.global {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = tokens.local {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    // MARK: Package

    /// Whether to install global monitors, local monitors, or both.
    package enum MonitorScope: Sendable {
        /// Monitors events outside the application's windows.
        case global
        /// Monitors events inside the application's windows.
        case local
        /// Monitors events both inside and outside the application's windows.
        case both
    }

    /// Whether the monitor is currently active.
    package private(set) var isRunning = false

    /// Installs the event monitors. Does nothing if already running.
    package func start() {
        guard !self.isRunning else { return }
        self.isRunning = true

        let handler = self._handler

        if self.scope == .global || self.scope == .both {
            let monitor = NSEvent.addGlobalMonitorForEvents(
                matching: self.mask,
            ) { event in
                _ = handler(event)
            }
            self._monitors.withLock { $0.global = monitor }
        }

        if self.scope == .local || self.scope == .both {
            let monitor = NSEvent.addLocalMonitorForEvents(
                matching: self.mask,
            ) { event in
                handler(event) ?? event
            }
            self._monitors.withLock { $0.local = monitor }
        }
    }

    /// Removes event monitors. Safe to call when already stopped.
    package func stop() {
        guard self.isRunning else { return }
        self.isRunning = false

        self._monitors.withLock { tokens in
            if let monitor = tokens.global {
                NSEvent.removeMonitor(monitor)
                tokens.global = nil
            }
            if let monitor = tokens.local {
                NSEvent.removeMonitor(monitor)
                tokens.local = nil
            }
        }
    }

    // MARK: Private

    private let mask: NSEvent.EventTypeMask
    private let scope: MonitorScope
    private let _handler: @Sendable (NSEvent) -> NSEvent?
    private let _monitors = Mutex(EventMonitorTokens())
}
