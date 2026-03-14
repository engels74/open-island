package import Foundation
package import OICore

// MARK: - SessionStore

/// Single source of truth for all session state.
///
/// Events enter through ``process(_:)`` and are dispatched to internal
/// handlers that mutate ``sessions``. State changes are broadcast to
/// subscribers via ``publishState()``.
package actor SessionStore {
    // MARK: Lifecycle

    package init() {}

    // MARK: Package

    /// Sorted snapshot of all active sessions, ordered by most-recent activity.
    package var currentSessions: [SessionState] {
        self.sessions.values.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// Look up a single session by ID.
    package func session(for id: String) -> SessionState? {
        self.sessions[id]
    }

    /// Single entry point for all session events.
    ///
    /// The `sending` annotation (SE-0430) documents ownership transfer into
    /// the actor's isolation domain — the canonical boundary where events
    /// cross from provider actors into the ``SessionStore``.
    package func process(_ event: sending SessionEvent) async {
        self.recordAudit(event)

        switch event {
        case let .providerEvent(providerEvent):
            handleProviderEvent(providerEvent)

        case let .permissionApproved(sessionID, requestID: requestID):
            handlePermissionApproved(sessionID, requestID: requestID)

        case let .permissionDenied(sessionID, requestID: requestID, reason: reason):
            handlePermissionDenied(sessionID, requestID: requestID, reason: reason)

        case let .archiveSession(sessionID):
            handleArchiveSession(sessionID)

        case let .userAction(sessionID, action: action):
            handleUserAction(sessionID, action: action)
        }
    }

    // MARK: Internal

    // MARK: Internal — stored properties for extensions

    /// Active sessions keyed by session ID.
    var sessions: [String: SessionState] = [:]

    /// UUID-keyed continuations for multi-subscriber broadcast (§2.2).
    var continuations: [UUID: AsyncStream<[SessionState]>.Continuation] = [:]

    /// Per-session tool trackers for tool lifecycle management (§2.4).
    var toolTrackers: [String: ToolTracker] = [:]

    /// Handle for the periodic health-check task (§2.5).
    var healthCheckTask: Task<Void, Never>?

    // MARK: Private

    /// Circular buffer storing the last 100 events for debugging.
    private var auditTrail: [SessionEvent?] = Array(repeating: nil, count: 100)
    private var auditIndex = 0

    private func recordAudit(_ event: SessionEvent) {
        self.auditTrail[self.auditIndex] = event
        self.auditIndex = (self.auditIndex + 1) % self.auditTrail.count
    }
}
