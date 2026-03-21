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

    public let id: String

    /// e.g., "Install hook scripts"
    public let title: String

    public let description: String
    public let isDestructive: Bool

    /// File paths that will be created or modified.
    public let affectedPaths: [String]
}
