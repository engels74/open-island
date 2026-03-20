/// A prerequisite that must be satisfied before a provider can be set up.
public struct ProviderPrerequisite: Sendable {
    // MARK: Lifecycle

    public init(id: String, description: String, checkDescription: String) {
        self.id = id
        self.description = description
        self.checkDescription = checkDescription
    }

    // MARK: Public

    /// Unique identifier for this prerequisite.
    public let id: String

    /// Human-readable description (e.g., "Claude CLI must be installed").
    public let description: String

    /// What the check verifies (e.g., "Claude CLI binary on PATH").
    public let checkDescription: String
}
