import Foundation
import Observation
import OICore

// MARK: - NotchActivityCoordinator

/// Coordinates notch auto-expand and bounce animations in response to session
/// state changes.
///
/// Observes ``SessionMonitor/instances`` for phase transitions:
/// - **Auto-expand**: opens the notch when a session enters
///   `.waitingForApproval`, subject to ``AppSettings/notchAutoExpand`` and a
///   debounce interval.
/// - **Bounce**: briefly sets ``isBouncing`` when a session enters
///   `.waitingForInput`` and the notch is closed.
/// - **Auto-collapse**: closes the notch after a timeout if the user has not
///   interacted since the auto-expand.
@Observable
@MainActor
package final class NotchActivityCoordinator {
    // MARK: Lifecycle

    package init(notchViewModel: NotchViewModel, sessionMonitor: SessionMonitor) {
        self.notchViewModel = notchViewModel
        self.sessionMonitor = sessionMonitor
    }

    deinit {
        observationTask?.cancel()
        autoCollapseTask?.cancel()
        bounceResetTask?.cancel()
    }

    // MARK: Package

    /// Whether a bounce animation is active. Views observe this to trigger
    /// a brief attention animation on the notch.
    package private(set) var isBouncing = false

    /// Begin observing session changes. Call once after initialization.
    package func start() {
        guard self.observationTask == nil else { return }
        self.observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let coordinator = self else { return }
                let currentPhases = coordinator.sessionMonitor.instances.map(\.phase)
                let monitor = coordinator.sessionMonitor
                // Wait for the next change via withObservationTracking.
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = monitor.instances
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard !Task.isCancelled, let coordinator = self else { return }
                let newPhases = coordinator.sessionMonitor.instances.map(\.phase)
                coordinator.handlePhaseChanges(previous: currentPhases, current: newPhases)
            }
        }
    }

    /// Stop observing session changes.
    package func stop() {
        self.observationTask?.cancel()
        self.observationTask = nil
        self.autoCollapseTask?.cancel()
        self.autoCollapseTask = nil
        self.bounceResetTask?.cancel()
        self.bounceResetTask = nil
    }

    /// Notify the coordinator that the user interacted with the notch manually.
    ///
    /// Cancels any pending auto-collapse timer so the notch stays in its
    /// user-chosen state.
    package func userDidInteract() {
        self.autoCollapseTask?.cancel()
        self.autoCollapseTask = nil
        self.didAutoExpand = false
    }

    // MARK: Private

    /// Minimum interval between auto-expand triggers.
    private static let debounceInterval: TimeInterval = 2.0

    /// Seconds before auto-collapsing after an auto-expand.
    private static let autoCollapseDelay: TimeInterval = 30.0

    /// Duration of the bounce animation flag.
    private static let bounceDuration: TimeInterval = 0.5

    @ObservationIgnored private let notchViewModel: NotchViewModel
    @ObservationIgnored private let sessionMonitor: SessionMonitor

    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var autoCollapseTask: Task<Void, Never>?
    @ObservationIgnored private var bounceResetTask: Task<Void, Never>?

    /// Timestamp of the last auto-expand for debouncing.
    @ObservationIgnored private var lastAutoExpandDate: Date?

    /// Whether the current open state was caused by auto-expand.
    @ObservationIgnored private var didAutoExpand = false

    /// Whether the terminal is visible. Stubbed as `false` until Phase 10
    /// provides `TerminalAppRegistry`.
    private var isTerminalVisible: Bool {
        false
    }

    // MARK: - Phase change handling

    private func handlePhaseChanges(previous: [SessionPhase], current: [SessionPhase]) {
        let hadApproval = previous.contains { phase in
            if case .waitingForApproval = phase { return true }
            return false
        }
        let hasApproval = current.contains { phase in
            if case .waitingForApproval = phase { return true }
            return false
        }

        let hadWaitingForInput = previous.contains { $0 == .waitingForInput }
        let hasWaitingForInput = current.contains { $0 == .waitingForInput }

        // Auto-expand: new permission request appeared.
        if hasApproval, !hadApproval {
            self.attemptAutoExpand()
        }

        // Bounce: new waitingForInput appeared.
        if hasWaitingForInput, !hadWaitingForInput {
            self.attemptBounce()
        }
    }

    // MARK: - Auto-expand

    private func attemptAutoExpand() {
        guard AppSettings.notchAutoExpand else { return }
        guard !self.isTerminalVisible else { return }
        guard self.notchViewModel.status == .closed else { return }

        // Debounce: skip if we auto-expanded recently.
        if let lastDate = lastAutoExpandDate,
           Date().timeIntervalSince(lastDate) < Self.debounceInterval {
            return
        }

        self.lastAutoExpandDate = Date()
        self.didAutoExpand = true
        self.notchViewModel.notchOpen(reason: .permissionRequest)
        self.scheduleAutoCollapse()
    }

    // MARK: - Auto-collapse

    private func scheduleAutoCollapse() {
        self.autoCollapseTask?.cancel()
        self.autoCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.autoCollapseDelay))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            guard self.didAutoExpand else { return }
            self.notchViewModel.notchClose()
            self.didAutoExpand = false
        }
    }

    // MARK: - Bounce

    private func attemptBounce() {
        // Don't bounce if the notch is already open — user is looking.
        guard self.notchViewModel.status == .closed else { return }

        self.bounceResetTask?.cancel()
        self.isBouncing = true
        self.bounceResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.bounceDuration))
            guard !Task.isCancelled else { return }
            self?.isBouncing = false
        }
    }
}
