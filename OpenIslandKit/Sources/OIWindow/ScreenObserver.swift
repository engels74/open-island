// @preconcurrency: NSApplication notifications, NSObjectProtocol predate Sendable annotations
@preconcurrency public import AppKit
public import Observation

// MARK: - ScreenObserver

/// Monitors screen configuration changes and publishes updated `NotchGeometry`.
///
/// Observes `NSApplication.didChangeScreenParametersNotification` with a 500ms
/// debounce to coalesce the rapid-fire notifications macOS sends when screens
/// connect, disconnect, or reconfigure.
@MainActor
@Observable
public final class ScreenObserver {
    // MARK: Lifecycle

    public init(selector: ScreenSelector = .automatic) {
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

    // MARK: Public

    public private(set) var geometry: NotchGeometry?

    public var selector: ScreenSelector {
        didSet {
            self.geometry = Self.computeGeometry(selector: self.selector)
        }
    }

    public var hasNotchScreen: Bool {
        self.geometry != nil
    }

    // MARK: Private

    private static let debounceNanoseconds: UInt64 = 500_000_000

    @ObservationIgnored private var notificationObserver: (any NSObjectProtocol)?

    @ObservationIgnored private var debounceTask: Task<Void, Never>?

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
                return
            }
            guard let self else { return }
            self.geometry = Self.computeGeometry(selector: self.selector)
        }
    }
}
