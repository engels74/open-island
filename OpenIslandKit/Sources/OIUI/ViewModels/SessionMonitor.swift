import Observation
package import OICore
package import OIState

// MARK: - SessionMonitor

/// Bridges ``SessionStore`` (actor) into the `@Observable` world for SwiftUI views.
///
/// Subscribes to ``SessionStore/sessionsStream()`` and publishes a filtered
/// snapshot of active sessions (excluding `.ended`). Convenience methods for
/// permission approval, denial, and session archival route through
/// ``SessionStore/process(_:)`` as ``SessionEvent`` values.
@MainActor
@Observable
package final class SessionMonitor {
    // MARK: Lifecycle

    package init(store: SessionStore) {
        self.store = store
    }

    deinit {
        streamTask?.cancel()
    }

    // MARK: Package

    /// Active sessions, sorted by most-recent activity, excluding ended sessions.
    package private(set) var instances: [SessionState] = []

    /// Start subscribing to the session store's stream.
    ///
    /// Call once after initialization. The subscription runs until ``stop()``
    /// is called or the monitor is deinitialized.
    package func start() {
        guard self.streamTask == nil else { return }
        self.streamTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.store.sessionsStream()
            for await sessions in stream {
                guard !Task.isCancelled else { break }
                self.instances = sessions.filter { $0.phase != .ended }
            }
        }
    }

    /// Stop the session stream subscription.
    package func stop() {
        self.streamTask?.cancel()
        self.streamTask = nil
    }

    /// Approve a pending permission request.
    package func approvePermission(sessionID: String, requestID: String) {
        Task {
            await self.store.process(.permissionApproved(sessionID, requestID: requestID))
        }
    }

    /// Deny a pending permission request.
    package func denyPermission(sessionID: String, requestID: String, reason: String? = nil) {
        Task {
            await self.store.process(.permissionDenied(sessionID, requestID: requestID, reason: reason))
        }
    }

    /// Archive (end) a session.
    package func archiveSession(sessionID: String) {
        Task {
            await self.store.process(.archiveSession(sessionID))
        }
    }

    // MARK: Private

    @ObservationIgnored private let store: SessionStore

    @ObservationIgnored private var streamTask: Task<Void, Never>?
}
