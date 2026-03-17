// @preconcurrency: AppKit types predate Sendable annotations
@preconcurrency import AppKit
import ApplicationServices
import Observation

// MARK: - AccessibilityPermissionManager

/// Checks and monitors macOS accessibility permission status.
///
/// On ``start()``, checks `AXIsProcessTrusted()` and shows an alert if
/// the app lacks accessibility permission. Polls every 5 seconds until
/// permission is granted, then stops polling automatically.
///
/// Observed by SwiftUI views via ``isAccessibilityGranted``.
@Observable
@MainActor
package final class AccessibilityPermissionManager {
    // MARK: Lifecycle

    package init() {}

    deinit {
        pollingTask?.cancel()
    }

    // MARK: Package

    /// Whether accessibility permission is currently granted.
    package private(set) var isAccessibilityGranted = false

    /// Begin checking accessibility permission. Call once after initialization.
    ///
    /// Checks `AXIsProcessTrusted()` immediately. If permission is missing,
    /// shows an alert with instructions and starts polling every 5 seconds
    /// until the user grants permission.
    package func start() {
        guard self.pollingTask == nil else { return }

        self.isAccessibilityGranted = AXIsProcessTrusted()

        if self.isAccessibilityGranted { return }

        self.showPermissionAlert()
        self.startPolling()
    }

    /// Stop monitoring accessibility permission.
    package func stop() {
        self.pollingTask?.cancel()
        self.pollingTask = nil
    }

    // MARK: Private

    /// Interval between permission checks.
    private static let pollingInterval: Duration = .seconds(5)

    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var hasShownAlert = false

    private func startPolling() {
        self.pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollingInterval)
                guard !Task.isCancelled, let self else { return }

                let granted = AXIsProcessTrusted()
                if granted {
                    self.isAccessibilityGranted = true
                    self.pollingTask?.cancel()
                    self.pollingTask = nil
                    return
                }
            }
        }
    }

    private func showPermissionAlert() {
        guard !self.hasShownAlert else { return }
        self.hasShownAlert = true

        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        Open Island needs accessibility permission to detect terminal windows.

        Go to System Settings \u{2192} Privacy & Security \u{2192} Accessibility \
        and add Open Island.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
