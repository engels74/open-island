/// The installation state of a provider on the user's system.
public enum ProviderInstallationStatus: Sendable {
    case notInstalled
    case installing
    case installed
    case failed(any Error & Sendable)
}
