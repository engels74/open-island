public import Foundation
public import OICore

extension SessionStore {
    /// Uses `.bufferingNewest(1)` so slow consumers always see the latest snapshot.
    public func sessionsStream() -> AsyncStream<[SessionState]> {
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
