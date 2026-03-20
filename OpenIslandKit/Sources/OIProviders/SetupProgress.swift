public import OICore

// MARK: - SetupProgress

/// Progress updates emitted during provider setup.
public enum SetupProgress: Sendable {
    case checkingPrerequisites
    case creatingBackup(path: String)
    case installingHooks
    case verifying
    case complete
    case failed(any Error & Sendable)
}

// MARK: - PrerequisiteCheckResult

/// The result of checking a single prerequisite.
public struct PrerequisiteCheckResult: Sendable {
    // MARK: Lifecycle

    public init(prerequisite: ProviderPrerequisite, passed: Bool, detail: String? = nil) {
        self.prerequisite = prerequisite
        self.passed = passed
        self.detail = detail
    }

    // MARK: Public

    /// Which prerequisite was checked.
    public let prerequisite: ProviderPrerequisite

    /// Whether the check passed.
    public let passed: Bool

    /// Optional detail message (e.g., version found, path resolved).
    public let detail: String?
}

// MARK: - VerificationResult

/// The result of verifying that a provider is correctly set up.
public struct VerificationResult: Sendable {
    // MARK: Lifecycle

    public init(success: Bool, message: String, details: [String]? = nil) {
        self.success = success
        self.message = message
        self.details = details
    }

    // MARK: Public

    /// Whether the provider is working correctly.
    public let success: Bool

    /// Summary message.
    public let message: String

    /// Optional additional details.
    public let details: [String]?
}

// MARK: - ProviderSetupError

/// Errors that can occur during provider setup/teardown.
public enum ProviderSetupError: Error, Sendable {
    case prerequisitesNotMet([PrerequisiteCheckResult])
    case backupFailed(ConfigBackupError)
    case hookInstallFailed(HookInstallError)
    case unsupportedProvider(ProviderID)
    case verificationFailed(String)
}
