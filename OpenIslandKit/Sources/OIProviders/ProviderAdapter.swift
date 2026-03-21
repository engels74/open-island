public import OICore

/// The core protocol that all provider implementations conform to.
public protocol ProviderAdapter: Sendable {
    var providerID: ProviderID { get }
    var metadata: ProviderMetadata { get }
    var transportType: ProviderTransportType { get }

    func start() async throws(ProviderStartupError)
    func stop() async
    func events() -> AsyncStream<ProviderEvent>

    /// Uses plain `throws` — failure modes are provider-specific and not a closed domain.
    func respondToPermission(
        _ request: PermissionRequest,
        decision: PermissionDecision,
    ) async throws

    func isSessionAlive(_ sessionID: String) -> Bool
}
