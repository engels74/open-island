/// The full set of requirements for setting up a provider.
public struct ProviderSetupRequirements: Sendable {
    // MARK: Lifecycle

    public init(prerequisites: [ProviderPrerequisite], steps: [ProviderSetupStep], estimatedDuration: String?) {
        self.prerequisites = prerequisites
        self.steps = steps
        self.estimatedDuration = estimatedDuration
    }

    // MARK: Public

    public let prerequisites: [ProviderPrerequisite]
    public let steps: [ProviderSetupStep]

    /// e.g., "~30 seconds". `nil` if unknown.
    public let estimatedDuration: String?
}
