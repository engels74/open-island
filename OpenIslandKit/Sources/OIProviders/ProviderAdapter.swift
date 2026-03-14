package import OICore

/// The core protocol that all provider implementations conform to.
///
/// Each supported AI coding assistant (Claude Code, Codex, Gemini CLI, OpenCode)
/// implements this protocol via a concrete actor. The ``ProviderRegistry`` manages
/// adapters through this interface.
package protocol ProviderAdapter: Sendable {
    var providerID: ProviderID { get }
    var metadata: ProviderMetadata { get }
    var transportType: ProviderTransportType { get }

    func start() async throws(ProviderStartupError)
    func stop() async

    /// Stream of normalized events from this provider.
    func events() -> AsyncStream<ProviderEvent>

    /// Respond to a permission request.
    /// Uses plain `throws` — failure modes are provider-specific and not a closed domain.
    func respondToPermission(
        _ request: PermissionRequest,
        decision: PermissionDecision,
    ) async throws

    /// Check if a session is still alive.
    func isSessionAlive(_ sessionID: String) -> Bool
}
