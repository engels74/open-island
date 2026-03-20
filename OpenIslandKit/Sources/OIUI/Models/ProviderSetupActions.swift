public import OICore

// MARK: - ProviderSetupActions

/// Closure-based bridge for provider setup operations.
///
/// Since OIUI cannot import OIProviders, these closures are injected by the
/// app target to connect the setup sheet UI to `ProviderSetupCoordinator`.
public struct ProviderSetupActions: Sendable {
    // MARK: Lifecycle

    public init(
        requirements: @escaping @Sendable (ProviderID) async -> ProviderSetupRequirements,
        install: @escaping @Sendable (ProviderID, @escaping @Sendable (String) -> Void) async throws -> Void,
        uninstall: @escaping @Sendable (ProviderID) async throws -> Void,
        enableProvider: @escaping @Sendable (ProviderID) async throws -> Void,
        disableProvider: @escaping @Sendable (ProviderID) async -> Void,
        isProviderRunning: @escaping @Sendable (ProviderID) async -> Bool,
    ) {
        self.requirements = requirements
        self.install = install
        self.uninstall = uninstall
        self.enableProvider = enableProvider
        self.disableProvider = disableProvider
        self.isProviderRunning = isProviderRunning
    }

    // MARK: Public

    /// Returns setup requirements for a provider.
    public let requirements: @Sendable (ProviderID) async -> ProviderSetupRequirements

    /// Runs installation, yielding progress descriptions. Throws on failure.
    public let install: @Sendable (ProviderID, @escaping @Sendable (String) -> Void) async throws -> Void

    /// Runs uninstallation. Throws on failure.
    public let uninstall: @Sendable (ProviderID) async throws -> Void

    /// Enables a provider at runtime (updates settings and starts the adapter).
    public let enableProvider: @Sendable (ProviderID) async throws -> Void

    /// Disables a provider at runtime (updates settings and stops the adapter).
    public let disableProvider: @Sendable (ProviderID) async -> Void

    /// Returns whether a provider adapter is currently running.
    public let isProviderRunning: @Sendable (ProviderID) async -> Bool
}
