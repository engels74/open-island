@preconcurrency package import AppKit
import Observation

// MARK: - ScreenObserver

/// Monitors screen configuration changes and publishes updated `NotchGeometry`.
///
/// Observes `NSApplication.didChangeScreenParametersNotification` with a 500ms
/// debounce to coalesce the rapid-fire notifications macOS sends when screens
/// connect, disconnect, or reconfigure.
@MainActor
@Observable
package final class ScreenObserver {
    // MARK: Lifecycle

    package init(selector: ScreenSelector = .automatic) {
        self.selector = selector
        self.geometry = Self.computeGeometry(selector: selector)
        self.startObserving()
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        debounceTask?.cancel()
    }

    // MARK: Package

    /// The current notch geometry, or `nil` when no notch screen is available.
    package private(set) var geometry: NotchGeometry?

    /// The current screen selector (automatic or user-selected).
    package var selector: ScreenSelector {
        didSet {
            self.geometry = Self.computeGeometry(selector: self.selector)
        }
    }

    /// Whether a notch-capable screen is currently connected.
    package var hasNotchScreen: Bool {
        self.geometry != nil
    }

    // MARK: Private

    /// Debounce interval in nanoseconds (500ms).
    private static let debounceNanoseconds: UInt64 = 500_000_000

    @ObservationIgnored private var notificationObserver: (any NSObjectProtocol)?

    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    /// Computes `NotchGeometry` for the screen identified by the given selector.
    private static func computeGeometry(selector: ScreenSelector) -> NotchGeometry? {
        guard let screen = selector.resolveScreen() else { return nil }
        guard let notchSize = screen.notchSize else { return nil }
        return NotchGeometry(notchSize: notchSize, screenFrame: screen.frame)
    }

    private func startObserving() {
        self.notificationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.scheduleUpdate()
            }
        }
    }

    private func scheduleUpdate() {
        self.debounceTask?.cancel()
        self.debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            } catch {
                return // cancelled
            }
            guard let self else { return }
            self.geometry = Self.computeGeometry(selector: self.selector)
        }
    }
}
