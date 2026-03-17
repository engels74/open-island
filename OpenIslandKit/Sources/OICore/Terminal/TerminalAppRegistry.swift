import Synchronization

// MARK: - TerminalAppInfo

/// Metadata for a known terminal application.
package struct TerminalAppInfo: Sendable, Hashable {
    /// The application's bundle identifier.
    package let bundleID: String

    /// Human-readable display name.
    package let displayName: String
}

// MARK: - TerminalAppRegistry

/// Thread-safe registry of known terminal and editor-with-terminal bundle IDs.
///
/// Ships with a built-in set of common terminals and editors. Providers can
/// register additional apps at runtime via ``register(bundleID:displayName:)``.
package final class TerminalAppRegistry: Sendable {
    // MARK: Package

    /// Shared singleton instance.
    package static let shared = TerminalAppRegistry()

    /// All currently registered terminal apps (built-in + runtime-added).
    package var allApps: [TerminalAppInfo] {
        let extra = self.runtimeApps.withLock { $0 }
        return Self.builtInApps + extra
    }

    /// Whether the given bundle identifier is a known terminal or
    /// editor-with-terminal.
    package func isTerminalBundleID(_ bundleID: String) -> Bool {
        if Self.builtInBundleIDs.contains(bundleID) {
            return true
        }
        return self.runtimeApps.withLock { apps in
            apps.contains { $0.bundleID == bundleID }
        }
    }

    /// Register an additional terminal app at runtime.
    ///
    /// Duplicate bundle IDs (including built-in ones) are silently ignored.
    package func register(bundleID: String, displayName: String) {
        self.runtimeApps.withLock { apps in
            guard !Self.builtInBundleIDs.contains(bundleID),
                  !apps.contains(where: { $0.bundleID == bundleID })
            else {
                return
            }
            apps.append(TerminalAppInfo(bundleID: bundleID, displayName: displayName))
        }
    }

    // MARK: Private

    /// Built-in terminal applications.
    private static let builtInApps: [TerminalAppInfo] = [
        // Dedicated terminals
        TerminalAppInfo(bundleID: "com.apple.Terminal", displayName: "Terminal"),
        TerminalAppInfo(bundleID: "com.googlecode.iterm2", displayName: "iTerm2"),
        TerminalAppInfo(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty"),
        TerminalAppInfo(bundleID: "io.alacritty", displayName: "Alacritty"),
        TerminalAppInfo(bundleID: "net.kovidgoyal.kitty", displayName: "kitty"),
        TerminalAppInfo(bundleID: "dev.warp.Warp-Stable", displayName: "Warp"),
        TerminalAppInfo(bundleID: "com.github.wez.wezterm", displayName: "WezTerm"),
        TerminalAppInfo(bundleID: "co.zeit.hyper", displayName: "Hyper"),
        TerminalAppInfo(bundleID: "com.raphaelamorim.rio", displayName: "Rio"),
        TerminalAppInfo(bundleID: "org.tabby", displayName: "Tabby"),
        // Editors with integrated terminals
        TerminalAppInfo(bundleID: "com.microsoft.VSCode", displayName: "VS Code"),
        TerminalAppInfo(bundleID: "com.todesktop.230313mzl4w4u92", displayName: "Cursor"),
        TerminalAppInfo(bundleID: "com.codeium.windsurf", displayName: "Windsurf"),
        TerminalAppInfo(bundleID: "dev.zed.Zed", displayName: "Zed"),
    ]

    /// Pre-computed set for O(1) built-in lookups.
    private static let builtInBundleIDs: Set<String> = Set(builtInApps.map(\.bundleID))

    private let runtimeApps = Mutex<[TerminalAppInfo]>([])
}
