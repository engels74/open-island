public import OICore

/// Summarizes a provider's current activity state for module visibility decisions.
///
/// Modules use this to make provider-aware UI decisions (e.g., showing Codex risk
/// level indicators or Claude-specific status) without coupling to a specific
/// provider's identity.
public struct ProviderActivitySummary: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        phase: SessionPhase,
        activeToolCount: Int = 0,
        pendingPermissionCount: Int = 0,
        currentRisk: PermissionRisk? = nil,
    ) {
        self.phase = phase
        self.activeToolCount = activeToolCount
        self.pendingPermissionCount = pendingPermissionCount
        self.currentRisk = currentRisk
    }

    // MARK: Public

    /// The provider's current session phase.
    public let phase: SessionPhase

    /// Number of tool calls currently in progress.
    public let activeToolCount: Int

    /// Number of permission requests awaiting user action.
    public let pendingPermissionCount: Int

    /// Highest risk level among pending permissions, if any.
    public let currentRisk: PermissionRisk?
}
