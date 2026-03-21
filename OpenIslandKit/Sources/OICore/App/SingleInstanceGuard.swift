// @preconcurrency: NSRunningApplication, NSWorkspace predate Sendable annotations
@preconcurrency import AppKit

// MARK: - RunningAppInfo

/// Protocol abstracting `NSRunningApplication` for testability.
public protocol RunningAppInfo: Sendable {
    var bundleIdentifier: String? { get }
    var processIdentifier: Int32 { get }
    var isTerminated: Bool { get }
}

// MARK: - NSRunningApplication + RunningAppInfo

extension NSRunningApplication: RunningAppInfo {}

// MARK: - SingleInstanceGuard

/// Prevents multiple instances of Open Island from running simultaneously.
///
/// Call `ensureSingleInstance()` as the first action in `App.init()`.
/// If an existing instance is detected, it is activated and the current
/// process terminates.
@MainActor
public enum SingleInstanceGuard {
    /// Checks for an already-running instance of this app. If one is found,
    /// activates it and terminates the current process.
    public static func ensureSingleInstance() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        let currentPID = getpid()
        let runningApps = NSWorkspace.shared.runningApplications

        guard let existing = findExistingInstance(
            bundleID: bundleID,
            currentPID: currentPID,
            runningApps: runningApps,
        )
        else {
            return
        }

        existing.activate()
        NSApp.terminate(nil)
    }

    /// Pure detection logic — finds an existing running instance of the same
    /// app, excluding the current process and terminated instances.
    ///
    /// Extracted for testability: callers can pass synthetic `RunningAppInfo`
    /// values instead of live `NSRunningApplication` objects.
    nonisolated public static func findExistingInstance<App: RunningAppInfo>(
        bundleID: String,
        currentPID: Int32,
        runningApps: some Sequence<App>,
    ) -> App? {
        runningApps.first { app in
            app.bundleIdentifier == bundleID
                && app.processIdentifier != currentPID
                && !app.isTerminated
        }
    }
}
