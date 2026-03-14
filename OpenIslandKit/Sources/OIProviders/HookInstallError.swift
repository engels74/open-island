package enum HookInstallError: Error, Sendable {
    case pythonNotFound
    case settingsFileCorrupted(path: String)
    case writePermissionDenied(path: String)
    case hookAlreadyInstalled
}
