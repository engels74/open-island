package import Foundation

// MARK: - GeminiHookInstaller

/// Installs and manages the Open Island hook script for Gemini CLI.
///
/// The installer:
/// 1. Detects (or accepts) a hook runtime via ``HookRuntimeDetector``
/// 2. Copies the bundled `open-island-gemini-hook.py` to `~/.gemini/hooks/`
/// 3. Registers hook commands in `~/.gemini/settings.json` for all 11 event types
/// 4. Supports deduplication, uninstallation, and status checking
///
/// Gemini CLI's settings format is similar to Claude Code — hooks are registered
/// in a `"hooks"` dictionary keyed by event type, each containing an array of
/// `{"type": "command", "command": "..."}` entries.
package struct GeminiHookInstaller: Sendable {
    // MARK: Package

    /// All Gemini CLI hook event types that Open Island registers for.
    package static let allHookEventTypes: [String] = [
        "SessionStart", "SessionEnd",
        "BeforeAgent", "AfterAgent",
        "BeforeModel", "AfterModel",
        "BeforeToolSelection",
        "BeforeTool", "AfterTool",
        "PreCompress",
        "Notification",
    ]

    /// The hook script filename.
    package static let hookScriptName = "open-island-gemini-hook.py"

    /// Install hooks for Gemini CLI.
    ///
    /// - Parameter hookCommand: Explicit hook command override.
    ///   If `nil`, ``HookRuntimeDetector/detect()`` is used.
    /// - Parameter geminiConfigDir: Override for the Gemini config directory.
    ///   Defaults to `~/.gemini`.
    /// - Parameter bundledScriptURL: Override for the bundled script location (for testing).
    package static func install(
        hookCommand: HookCommand? = nil,
        geminiConfigDir: URL? = nil,
        bundledScriptURL: URL? = nil,
    ) async throws(HookInstallError) {
        // 1. Resolve hook command
        let resolvedCommand = if let hookCommand {
            hookCommand
        } else {
            try HookRuntimeDetector.detect()
        }

        let configDir = geminiConfigDir ?? self.defaultGeminiConfigDir()

        // 2. Create hooks directory
        let hooksDir = configDir.appendingPathComponent("hooks", isDirectory: true)
        try self.createDirectoryIfNeeded(at: hooksDir)

        // 3. Copy bundled script
        let scriptSource = try resolveBundledScript(override: bundledScriptURL)
        let scriptDest = hooksDir.appendingPathComponent(Self.hookScriptName)
        try self.copyScript(from: scriptSource, to: scriptDest)

        // 4. Update settings.json
        let settingsURL = configDir.appendingPathComponent("settings.json")
        let command = resolvedCommand.commandString(scriptPath: scriptDest.path)
        try self.updateSettings(at: settingsURL, command: command)
    }

    /// Remove all Open Island hooks from Gemini CLI.
    ///
    /// - Parameter geminiConfigDir: Override for the Gemini config directory.
    ///   Defaults to `~/.gemini`.
    package static func uninstall(
        geminiConfigDir: URL? = nil,
    ) async throws(HookInstallError) {
        let configDir = geminiConfigDir ?? self.defaultGeminiConfigDir()

        // 1. Remove hook script
        let scriptPath = configDir
            .appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent(Self.hookScriptName)

        if FileManager.default.fileExists(atPath: scriptPath.path) {
            do {
                try FileManager.default.removeItem(at: scriptPath)
            } catch {
                throw .writePermissionDenied(path: scriptPath.path)
            }
        }

        // 2. Remove entries from settings.json
        let settingsURL = configDir.appendingPathComponent("settings.json")
        try self.removeHooksFromSettings(at: settingsURL)
    }

    /// Check whether Open Island hooks are currently installed for Gemini CLI.
    ///
    /// - Parameter geminiConfigDir: Override for the Gemini config directory.
    ///   Defaults to `~/.gemini`.
    /// - Returns: `true` if the hook script exists and settings.json contains
    ///   at least one Open Island hook entry.
    package static func isInstalled(
        geminiConfigDir: URL? = nil,
    ) -> Bool {
        let configDir = geminiConfigDir ?? self.defaultGeminiConfigDir()

        let scriptPath = configDir
            .appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent(Self.hookScriptName)

        guard FileManager.default.fileExists(atPath: scriptPath.path) else {
            return false
        }

        let settingsURL = configDir.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any]
        else {
            return false
        }

        for (_, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            for entry in entries {
                if let cmd = entry["command"] as? String,
                   cmd.contains(Self.hookScriptName) {
                    return true
                }
            }
        }

        return false
    }

    // MARK: Private

    private static func defaultGeminiConfigDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
    }

    private static func createDirectoryIfNeeded(at url: URL) throws(HookInstallError) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
            )
        } catch {
            throw .writePermissionDenied(path: url.path)
        }
    }

    private static func resolveBundledScript(
        override: URL?,
    ) throws(HookInstallError) -> URL {
        if let override {
            return override
        }

        guard let url = Bundle.module.url(
            forResource: "open-island-gemini-hook",
            withExtension: "py",
            subdirectory: "Hooks/GeminiCLI",
        )
        else {
            guard let url = Bundle.module.url(
                forResource: "open-island-gemini-hook",
                withExtension: "py",
            )
            else {
                throw .bundleResourceMissing(path: "Bundle.module/open-island-gemini-hook.py")
            }
            return url
        }
        return url
    }

    private static func copyScript(from source: URL, to destination: URL) throws(HookInstallError) {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw .writePermissionDenied(path: destination.path)
        }
    }

    /// Read, modify, and write back `settings.json` with our hook commands.
    private static func updateSettings(
        at settingsURL: URL,
        command: String,
    ) throws(HookInstallError) {
        var root = try readSettingsJSON(at: settingsURL)

        var hooks = root["hooks"] as? [String: Any] ?? [:]

        for eventType in self.allHookEventTypes {
            var entries = hooks[eventType] as? [[String: Any]] ?? []

            // Deduplication: check if we already have an open-island hook
            if let existingIndex = entries.firstIndex(where: { entry in
                guard let cmd = entry["command"] as? String else { return false }
                return cmd.contains(Self.hookScriptName)
            }) {
                entries[existingIndex] = ["type": "command", "command": command]
            } else {
                entries.append(["type": "command", "command": command])
            }

            hooks[eventType] = entries
        }

        root["hooks"] = hooks
        try self.writeSettingsJSON(root, to: settingsURL)
    }

    /// Remove all Open Island hook entries from settings.json.
    private static func removeHooksFromSettings(
        at settingsURL: URL,
    ) throws(HookInstallError) {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }

        var root = try readSettingsJSON(at: settingsURL)

        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for eventType in self.allHookEventTypes {
            guard var entries = hooks[eventType] as? [[String: Any]] else { continue }
            entries.removeAll { entry in
                guard let cmd = entry["command"] as? String else { return false }
                return cmd.contains(Self.hookScriptName)
            }
            if entries.isEmpty {
                hooks.removeValue(forKey: eventType)
            } else {
                hooks[eventType] = entries
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }

        try self.writeSettingsJSON(root, to: settingsURL)
    }

    private static func readSettingsJSON(
        at url: URL,
    ) throws(HookInstallError) -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .writePermissionDenied(path: url.path)
        }

        if data.isEmpty {
            return [:]
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HookInstallError.settingsFileCorrupted(path: url.path)
            }
            return json
        } catch is HookInstallError {
            throw .settingsFileCorrupted(path: url.path)
        } catch {
            throw .settingsFileCorrupted(path: url.path)
        }
    }

    private static func writeSettingsJSON(
        _ json: [String: Any],
        to url: URL,
    ) throws(HookInstallError) {
        let data: Data
        do {
            data = try JSONSerialization.data(
                withJSONObject: json,
                options: [.prettyPrinted, .sortedKeys],
            )
        } catch {
            throw .settingsFileCorrupted(path: url.path)
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw .writePermissionDenied(path: url.path)
        }
    }
}
