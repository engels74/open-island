package import Foundation
package import OICore

extension SessionStore {
    /// Creates a new subscriber stream that receives session state snapshots.
    ///
    /// Each subscriber immediately receives the current state and all subsequent
    /// updates broadcast via ``publishState()``. The stream uses `.bufferingNewest(1)`
    /// so slow consumers always see the latest snapshot.
    package func sessionsStream() -> AsyncStream<[SessionState]> {
        let (stream, continuation) = AsyncStream<[SessionState]>.makeStream(
            bufferingPolicy: .bufferingNewest(1),
        )

        let id = UUID()

        continuation.onTermination = { _ in
            Task { await self.removeContinuation(id) }
        }

        continuations[id] = continuation
        continuation.yield(self.sortedSessions())
        return stream
    }

    /// Broadcasts the current session state to all active subscribers.
    func publishState() {
        let sorted = self.sortedSessions()
        for continuation in continuations.values {
            continuation.yield(sorted)
        }
    }

    // MARK: - Private

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func sortedSessions() -> [SessionState] {
        sessions.values.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }
}
