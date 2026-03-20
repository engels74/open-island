/// A single step in a provider's setup process.
public struct ProviderSetupStep: Sendable {
    // MARK: Lifecycle

    public init(id: String, title: String, description: String, isDestructive: Bool, affectedPaths: [String]) {
        self.id = id
        self.title = title
        self.description = description
        self.isDestructive = isDestructive
        self.affectedPaths = affectedPaths
    }

    // MARK: Public

    /// Unique identifier for this step.
    public let id: String

    /// Human-readable title (e.g., "Install hook scripts").
    public let title: String

    /// Detailed description of what this step does.
    public let description: String

    /// Whether this step makes destructive changes that are hard to undo.
    public let isDestructive: Bool

    /// File paths that will be created or modified by this step.
    public let affectedPaths: [String]
}
