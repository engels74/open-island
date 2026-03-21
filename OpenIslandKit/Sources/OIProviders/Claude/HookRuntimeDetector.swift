import Foundation

// MARK: - HookCommand

/// The resolved command used to execute the hook script.
///
/// Either `uv run` (which manages its own Python) or a direct Python interpreter path.
package enum HookCommand: Sendable, Equatable {
    /// Use `uv run` to execute the script with an auto-managed Python >= 3.14.
    case uv(path: String)
    /// Use a direct Python 3.14+ interpreter.
    case python(path: String)

    // MARK: Package

    /// Build the full shell command string for a given script path.
    ///
    /// - Parameter scriptPath: Absolute path to the hook Python script.
    /// - Returns: A shell-safe command string.
    package func commandString(scriptPath: String) -> String {
        switch self {
        case let .uv(uvPath):
            "\(Self.shellQuote(uvPath)) run --python '>=3.14' \(Self.shellQuote(scriptPath))"
        case let .python(pythonPath):
            "\(Self.shellQuote(pythonPath)) \(Self.shellQuote(scriptPath))"
        }
    }

    // MARK: Private

    /// Shell-quote a path for safe embedding in a command string.
    /// Uses single quotes to prevent glob/variable expansion, with
    /// embedded single quotes escaped as `'\''`.
    private static func shellQuote(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

// MARK: - HookRuntimeDetector

/// Locates a usable runtime for executing the Open Island hook script.
///
/// Detection tiers (checked in order):
/// 1. **`uv`**: Preferred — handles Python version management automatically.
/// 2. **PATH Python 3.14+**: Versioned binaries and common names in PATH.
/// 3. **Homebrew Python 3.14+**: Keg-installed Python on macOS.
///
/// If Python is found but is older than 3.14, throws
/// ``HookInstallError/pythonVersionTooOld(found:required:)``.
/// If no runtime is found at all, throws ``HookInstallError/pythonNotFound``.
package enum HookRuntimeDetector {
    // MARK: Package

    /// The minimum required Python minor version.
    package static let minimumPythonMinor = 14

    /// Detect a usable hook runtime, returning the resolved command.
    ///
    /// - Throws: ``HookInstallError/pythonNotFound`` or
    ///   ``HookInstallError/pythonVersionTooOld(found:required:)``
    package static func detect() throws(HookInstallError) -> HookCommand {
        if let uvPath = findUV() {
            return .uv(path: uvPath)
        }

        var bestVersionFound: String?

        let pathCandidates = [
            resolveInPATH("python3.14"),
            resolveInPATH("python3"),
            "/usr/bin/python3",
            resolveInPATH("python"),
        ]

        for candidate in pathCandidates {
            guard let path = candidate,
                  FileManager.default.isExecutableFile(atPath: path)
            else { continue }

            switch self.checkPythonVersion(at: path) {
            case .suitable:
                return .python(path: path)
            case let .tooOld(version):
                bestVersionFound = version
            case .notPython:
                continue
            }
        }

        let homebrewCandidates = [
            // Apple Silicon keg
            "/opt/homebrew/opt/python@3.14/libexec/bin/python3.14",
            // Intel keg
            "/usr/local/opt/python@3.14/libexec/bin/python3.14",
            // Apple Silicon default (may not be 3.14)
            "/opt/homebrew/bin/python3",
            // Intel default (may not be 3.14)
            "/usr/local/bin/python3",
        ]

        for candidate in homebrewCandidates {
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }

            switch self.checkPythonVersion(at: candidate) {
            case .suitable:
                return .python(path: candidate)
            case let .tooOld(version):
                bestVersionFound = version
            case .notPython:
                continue
            }
        }

        if let version = bestVersionFound {
            throw .pythonVersionTooOld(found: version, required: "3.\(self.minimumPythonMinor)")
        }
        throw .pythonNotFound
    }

    // MARK: Private

    /// Result of checking a Python interpreter's version.
    private enum VersionCheckResult {
        case suitable
        case tooOld(version: String)
        case notPython
    }

    /// Look for `uv` in common locations.
    private static func findUV() -> String? {
        if let path = resolveInPATH("uv") {
            return path
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.cargo/bin/uv",
            "\(home)/.local/bin/uv",
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }

    /// Check whether the Python interpreter at `path` is version 3.14+.
    private static func checkPythonVersion(at path: String) -> VersionCheckResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .notPython
        }

        guard process.terminationStatus == 0 else { return .notPython }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return self.parseVersionOutput(output)
    }

    private static func parseVersionOutput(_ output: String) -> VersionCheckResult {
        // Expected format: "Python 3.14.0a1\n" or "Python 3.13.2\n"
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("Python ") else { return .notPython }

        let versionString = String(trimmed.dropFirst("Python ".count))

        // Split "3.14.0a1" into components
        let parts = versionString.split(separator: ".")
        guard parts.count >= 2,
              let major = Int(parts[0]),
              // Minor may have alpha/beta/rc suffix: "14a1" → parse leading digits
              let minor = Int(parts[1].prefix(while: \.isWholeNumber))
        else {
            return .notPython
        }

        guard major == 3 else {
            return .tooOld(version: versionString)
        }

        if minor >= self.minimumPythonMinor {
            return .suitable
        }

        return .tooOld(version: versionString)
    }

    /// Resolve a binary name to an absolute path using `which` with augmented PATH.
    private static func resolveInPATH(_ name: String) -> String? {
        UserPATH.resolveInPATH(name)
    }
}
