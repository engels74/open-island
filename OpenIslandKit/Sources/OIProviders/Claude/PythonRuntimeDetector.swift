package import Foundation

// MARK: - PythonRuntimeDetector

/// Locates a usable Python 3 interpreter on the system.
///
/// Search order:
/// 1. `python3` in PATH
/// 2. `/usr/bin/python3`
/// 3. `/usr/local/bin/python3`
/// 4. `python` in PATH (verified to be Python 3)
package enum PythonRuntimeDetector {
    // MARK: Package

    /// Detect a Python 3 runtime, returning the absolute path to the interpreter.
    ///
    /// - Throws: ``HookInstallError/pythonNotFound`` if no Python 3 interpreter is found.
    package static func detect() throws(HookInstallError) -> String {
        // 1. python3 in PATH
        if let path = resolveInPATH("python3"), isPython3(at: path) {
            return path
        }

        // 2. Well-known locations
        for candidate in ["/usr/bin/python3", "/usr/local/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: candidate), self.isPython3(at: candidate) {
                return candidate
            }
        }

        // 3. python in PATH (verify it's Python 3)
        if let path = resolveInPATH("python"), isPython3(at: path) {
            return path
        }

        throw .pythonNotFound
    }

    // MARK: Private

    /// Resolve a binary name to an absolute path using `which`.
    private static func resolveInPATH(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let path, !path.isEmpty else { return nil }
        return path
    }

    /// Verify that the interpreter at the given path is Python 3.
    private static func isPython3(at path: String) -> Bool {
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
            return false
        }

        guard process.terminationStatus == 0 else { return false }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Expect "Python 3.x.y"
        return output.contains("Python 3")
    }
}
