// MARK: - HookInstallError

package enum HookInstallError: Error, Sendable {
    case pythonNotFound
    case pythonVersionTooOld(found: String, required: String)
    case settingsFileCorrupted(path: String)
    case writePermissionDenied(path: String)
    case hookAlreadyInstalled
}

// MARK: CustomStringConvertible

extension HookInstallError: CustomStringConvertible {
    package var description: String {
        switch self {
        case .pythonNotFound:
            "No Python 3.14+ runtime found. Install uv (https://docs.astral.sh/uv/) for automatic Python management, or install Python 3.14+ directly."
        case let .pythonVersionTooOld(found, required):
            "Python \(found) is too old. Version \(required)+ is required."
        case let .settingsFileCorrupted(path):
            "Claude Code settings file is corrupted: \(path)"
        case let .writePermissionDenied(path):
            "Write permission denied: \(path)"
        case .hookAlreadyInstalled:
            "Hook is already installed."
        }
    }
}
