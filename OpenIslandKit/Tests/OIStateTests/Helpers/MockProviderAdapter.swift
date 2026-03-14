import Foundation
@testable import OICore
@testable import OIProviders

/// A minimal mock that conforms to ``ProviderAdapter`` for testing
/// health-check zombie detection in ``SessionStore``.
final class MockProviderAdapter: ProviderAdapter, @unchecked Sendable {
    // MARK: Lifecycle

    init(
        providerID: ProviderID = .claude,
        alive: Bool = true,
    ) {
        self.providerID = providerID
        self.metadata = .metadata(for: providerID)
        self.transportType = self.metadata.transportType
        self.alive = alive

        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream()
        self.eventsStream = stream
        self.eventsContinuation = continuation
    }

    // MARK: Internal

    let providerID: ProviderID
    let metadata: ProviderMetadata
    let transportType: ProviderTransportType

    /// When `false`, the health check treats the session as a zombie.
    var alive: Bool

    func start() async throws(ProviderStartupError) {}
    func stop() async {
        self.eventsContinuation.finish()
    }

    func events() -> AsyncStream<ProviderEvent> {
        self.eventsStream
    }

    func respondToPermission(
        _ request: PermissionRequest,
        decision: PermissionDecision,
    ) async throws {}

    func isSessionAlive(_ sessionID: String) -> Bool {
        self.alive
    }

    // MARK: Private

    private let eventsContinuation: AsyncStream<ProviderEvent>.Continuation
    private let eventsStream: AsyncStream<ProviderEvent>
}
