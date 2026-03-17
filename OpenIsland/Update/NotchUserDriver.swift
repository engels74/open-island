import Foundation
import Sparkle

// MARK: - NotchUserDriver

/// Sparkle user driver that intercepts update UI callbacks and exposes
/// update state for the in-notch overlay instead of showing standard
/// Sparkle windows.
///
/// All methods are `@MainActor`-isolated (app target default) to match
/// the `SPUUserDriver` protocol's main-thread requirements.
final class NotchUserDriver: NSObject, SPUUserDriver {
    /// Observable state for the notch update view.
    private(set) var updateState = UpdateState()

    // MARK: - SPUUserDriver

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func showCanCheck(forUpdates canCheckForUpdates: Bool) {
        self.updateState.canCheckForUpdates = canCheckForUpdates
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping @Sendable (SUUpdatePermissionResponse) -> Void,
    ) {
        // Auto-allow update checks.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping @Sendable () -> Void) {
        self.updateState.phase = .checking
        self.updateState.cancellation = cancellation
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void,
    ) {
        self.updateState.availableVersion = appcastItem.displayVersionString
        self.updateState.phase = .available
        self.updateState.userUpdateChoice = reply
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        // Release notes display not needed for the minimal notch UI.
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        // Silently ignore — release notes are optional.
    }

    func showUpdateNotFoundWithError(
        _ error: any Error,
        acknowledgement: @escaping @Sendable () -> Void,
    ) {
        self.updateState.phase = .idle
        acknowledgement()
    }

    func showUpdaterError(
        _ error: any Error,
        acknowledgement: @escaping @Sendable () -> Void,
    ) {
        self.updateState.phase = .idle
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping @Sendable () -> Void) {
        self.updateState.phase = .downloading
        self.updateState.downloadProgress = 0
        self.updateState.expectedContentLength = 0
        self.updateState.downloadedLength = 0
        self.updateState.cancellation = cancellation
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        self.updateState.expectedContentLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        guard self.updateState.expectedContentLength > 0 else { return }
        self.updateState.downloadedLength += length
        self.updateState.downloadProgress =
            Double(self.updateState.downloadedLength) / Double(self.updateState.expectedContentLength)
    }

    func showDownloadDidStartExtractingUpdate() {
        self.updateState.phase = .extracting
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        self.updateState.extractionProgress = progress
    }

    func showReady(
        toInstallAndRelaunch installAndRelaunch: @escaping @Sendable (SPUUserUpdateChoice) -> Void,
    ) {
        self.updateState.phase = .readyToInstall
        self.updateState.installAndRelaunch = installAndRelaunch
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping @Sendable () -> Void,
    ) {
        self.updateState.phase = .installing
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping @Sendable () -> Void,
    ) {
        self.updateState.phase = .idle
        acknowledgement()
    }

    func showSendingTerminationSignal() {
        // App is about to terminate for update — nothing to display.
    }

    func dismissUpdateInstallation() {
        self.updateState.reset()
    }
}
