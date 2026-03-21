public import Foundation
public import OICore

// MARK: - SessionStore

/// Single source of truth for all session state.
public actor SessionStore {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public var currentSessions: [SessionState] {
        self.sessions.values.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    public func session(for id: String) -> SessionState? {
        self.sessions[id]
    }

    /// Single entry point for all session events.
    ///
    /// The `sending` annotation (SE-0430) documents ownership transfer into
    /// the actor's isolation domain — the canonical boundary where events
    /// cross from provider actors into the ``SessionStore``.
    public func process(_ event: sending SessionEvent) async {
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

    var sessions: [String: SessionState] = [:]

    /// Multi-subscriber broadcast (§2.2).
    var continuations: [UUID: AsyncStream<[SessionState]>.Continuation] = [:]

    /// Tool lifecycle management (§2.4).
    var toolTrackers: [String: ToolTracker] = [:]

    /// Periodic health-check (§2.5).
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
