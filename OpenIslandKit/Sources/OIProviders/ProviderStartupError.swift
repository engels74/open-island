package enum ProviderStartupError: Error, Sendable {
    case binaryNotFound(String)
    case configNotFound(path: String)
    case configParseError(path: String, underlying: any Error)
    case socketCreationFailed(path: String)
    case alreadyRunning
}
