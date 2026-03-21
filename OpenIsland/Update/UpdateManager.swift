import Foundation
import Observation
import os
import Sparkle

// MARK: - UpdatePhase

/// Phases of the Sparkle update lifecycle visible to the notch UI.
enum UpdatePhase: Sendable {
    case idle
    case checking
    case available
    case downloading
    case extracting
    case readyToInstall
    case installing
}

// MARK: - UpdateState

/// Observable snapshot of the current update state, driven by ``NotchUserDriver``.
@Observable
final class UpdateState {
    var phase: UpdatePhase = .idle
    var canCheckForUpdates = false
    var availableVersion: String?

    var downloadProgress: Double = 0
    var extractionProgress: Double = 0

    // Internal bookkeeping — not observed by UI.
    @ObservationIgnored var expectedContentLength: UInt64 = 0
    @ObservationIgnored var downloadedLength: UInt64 = 0
    @ObservationIgnored var userUpdateChoice: (@Sendable (SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored var installAndRelaunch: (@Sendable (SPUUserUpdateChoice) -> Void)?
    @ObservationIgnored var cancellation: (@Sendable () -> Void)?

    func reset() {
        self.phase = .idle
        self.availableVersion = nil
        self.downloadProgress = 0
        self.extractionProgress = 0
        self.expectedContentLength = 0
        self.downloadedLength = 0
        self.userUpdateChoice = nil
        self.installAndRelaunch = nil
        self.cancellation = nil
    }
}

// MARK: - UpdateManager

/// Wraps Sparkle's `SPUUpdater` behind a `@MainActor`-isolated interface.
///
/// Sparkle types do not conform to `Sendable`. By keeping the entire
/// interaction on the main actor (which is the app target's default
/// isolation), no `@unchecked Sendable` conformance is needed.
@Observable
final class UpdateManager {
    // MARK: Lifecycle

    init() {
        let driver = NotchUserDriver()
        self.userDriver = driver
        self.updater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: driver,
            delegate: nil,
        )
        self.state = driver.updateState
    }

    // MARK: Internal

    let state: UpdateState

    var canCheckForUpdates: Bool {
        self.updater.canCheckForUpdates
    }

    /// Starts the Sparkle updater, enabling automatic background checks.
    func start() {
        if let edKey = Bundle.main.infoDictionary?["SUPublicEDKey"] as? String, edKey.isEmpty {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "OpenIsland", category: "UpdateManager")
                .warning(
                    "SUPublicEDKey is empty — update signature verification disabled. Generate keys with Sparkle's generate_keys.",
                )
        }

        do {
            try self.updater.start()
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "OpenIsland", category: "UpdateManager")
                .error("Failed to start SPUUpdater: \(error)")
        }
    }

    func checkForUpdates() {
        self.updater.checkForUpdates()
    }

    func acceptUpdate() {
        self.state.userUpdateChoice?(.install)
    }

    func skipUpdate() {
        self.state.userUpdateChoice?(.skip)
        self.state.reset()
    }

    func dismissUpdate() {
        self.state.userUpdateChoice?(.dismiss)
        self.state.reset()
    }

    func installAndRelaunch() {
        self.state.installAndRelaunch?(.install)
    }

    // MARK: Private

    @ObservationIgnored private let userDriver: NotchUserDriver
    @ObservationIgnored private let updater: SPUUpdater
}
