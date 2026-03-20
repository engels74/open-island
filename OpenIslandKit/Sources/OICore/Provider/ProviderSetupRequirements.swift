/// The full set of requirements for setting up a provider.
public struct ProviderSetupRequirements: Sendable {
    // MARK: Lifecycle

    public init(prerequisites: [ProviderPrerequisite], steps: [ProviderSetupStep], estimatedDuration: String?) {
        self.prerequisites = prerequisites
        self.steps = steps
        self.estimatedDuration = estimatedDuration
    }

    // MARK: Public

    /// Prerequisites that must be met before setup can proceed.
    public let prerequisites: [ProviderPrerequisite]

    /// Ordered steps to configure the provider.
    public let steps: [ProviderSetupStep]

    /// Human-readable estimate (e.g., "~30 seconds"), or `nil` if unknown.
    public let estimatedDuration: String?
}
