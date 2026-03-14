package import Foundation
import OICore
package import OIProviders
import OSLog

private let logger = Logger(subsystem: "com.openisland", category: "SessionHealthCheck")

extension SessionStore {
    /// Start the periodic health-check loop.
    ///
    /// Every 3 seconds, iterates all non-ended sessions and asks the
    /// provider adapter whether each session is still alive. Zombie
    /// sessions (where the provider reports the session is gone) are
    /// transitioned to `.ended`.
    package func startHealthCheck(registry: ProviderRegistry) {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                await self.checkZombieSessions(registry: registry)
            }
        }
    }

    /// Cancel the periodic health-check loop.
    package func stopHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
    }

    // MARK: - Private

    private func checkZombieSessions(registry: ProviderRegistry) async {
        let activeSessions = sessions.filter { $0.value.phase != .ended }

        for (sessionID, session) in activeSessions {
            guard let adapter = await registry.adapter(for: session.providerID) else {
                continue
            }

            let alive = adapter.isSessionAlive(sessionID)

            if !alive {
                logger.info("Health check: session \(sessionID) is no longer alive, transitioning to .ended")
                self.endSession(sessionID)
            }
        }
    }

    /// Transition a session to `.ended` if the current phase allows it.
    private func endSession(_ sessionID: String) {
        guard var session = sessions[sessionID] else { return }

        guard session.phase != .ended else { return }
        guard session.phase.canTransition(to: .ended) else {
            logger.warning("Health check: cannot transition session \(sessionID) from \(String(describing: session.phase)) to .ended")
            return
        }

        session.phase = .ended
        session.lastActivityAt = Date()
        sessions[sessionID] = session
        publishState()
    }
}
