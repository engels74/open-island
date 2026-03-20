package import Foundation
import Synchronization

// MARK: - UserPATH

/// Augments the process PATH with well-known user binary directories.
///
/// macOS GUI apps inherit a minimal PATH (`/usr/bin:/bin:/usr/sbin:/sbin`) that
/// excludes directories where user-installed tools live (`~/.local/bin`,
/// `/opt/homebrew/bin`, `~/.cargo/bin`, etc.). This helper builds an augmented
/// PATH once, caches it, and provides `resolveInPATH(_:)` for binary lookup.
package enum UserPATH {
    // MARK: Package

    /// Resolve a binary name to an absolute path using `/usr/bin/which`
    /// with an augmented PATH that includes well-known user directories.
    ///
    /// The augmented PATH is computed once and cached for the process lifetime.
    package static func resolveInPATH(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.environment = ["PATH": self.augmentedPATH()]

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

    // MARK: Private

    /// Cached augmented PATH string, computed once.
    private static let cachedPATH = Mutex<String?>(nil)

    /// Returns the cached augmented PATH, building it on first access.
    private static func augmentedPATH() -> String {
        self.cachedPATH.withLock { cached in
            if let existing = cached {
                return existing
            }
            let built = self.buildAugmentedPATH()
            cached = built
            return built
        }
    }

    /// Build the augmented PATH by combining the current process PATH
    /// with well-known user binary directories.
    ///
    /// All candidate directories are included regardless of whether they
    /// currently exist on disk. `/usr/bin/which` silently skips non-existent
    /// PATH entries, so this is safe and ensures the cached result remains
    /// valid even if directories are created later (e.g. after a tool install).
    private static func buildAugmentedPATH() -> String {
        let currentPATH = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let existingDirs = Set(currentPATH.split(separator: ":").map(String.init))

        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Well-known directories where user-installed binaries live.
        // Prepended before the process PATH so user-installed tools
        // (claude, codex, etc.) take priority over any system copies.
        // Within this list, earlier entries have higher priority.
        let candidates = [
            "\(home)/.local/bin", // claude, pip-installed tools
            "/opt/homebrew/bin", // Homebrew (Apple Silicon)
            "/opt/homebrew/sbin", // Homebrew sbin (Apple Silicon)
            "/usr/local/bin", // Homebrew (Intel), manual installs
            "/usr/local/sbin", // sbin (Intel)
            "\(home)/.cargo/bin", // Rust toolchain, uv
            "\(home)/.bun/bin", // Bun
        ]

        // Include all candidates not already in PATH — even non-existent
        // directories — so that tools installed after cache creation are found.
        var components: [String] = []
        for candidate in candidates where !existingDirs.contains(candidate) {
            components.append(candidate)
        }
        components.append(currentPATH)

        return components.joined(separator: ":")
    }
}
