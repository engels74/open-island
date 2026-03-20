package import Foundation

// MARK: - ClaudeHookInstaller

/// Installs and manages the Open Island hook script for Claude Code.
///
/// The installer:
/// 1. Detects (or accepts) a hook runtime via ``HookRuntimeDetector``
/// 2. Copies the bundled `open-island-claude-hook.py` to `~/.claude/hooks/`
/// 3. Registers hook commands in `~/.claude/settings.json` for all 17 event types
/// 4. Supports deduplication, uninstallation, and status checking
package struct ClaudeHookInstaller: Sendable {
    // MARK: Package

    /// All Claude Code hook event types that Open Island registers for.
    package static let allHookEventTypes: [String] = [
        // Session lifecycle
        "SessionStart", "SessionEnd",
        // Agentic loop (PreToolUse excluded — upstream bug #15897)
        "UserPromptSubmit", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Stop", "Notification",
        // Team
        "SubagentStart", "SubagentStop", "TeammateIdle", "TaskCompleted",
        // Maintenance
        "PreCompact", "ConfigChange", "WorktreeCreate", "WorktreeRemove",
        // Setup
        "Setup",
    ]

    /// The hook script filename.
    package static let hookScriptName = "open-island-claude-hook.py"

    /// Install hooks for Claude Code.
    ///
    /// - Parameter hookCommand: Explicit hook command override.
    ///   If `nil`, ``HookRuntimeDetector/detect()`` is used.
    /// - Parameter claudeConfigDir: Override for the Claude config directory.
    ///   Defaults to `~/.claude`.
    /// - Parameter bundledScriptURL: Override for the bundled script location (for testing).
    package static func install(
        hookCommand: HookCommand? = nil,
        claudeConfigDir: URL? = nil,
        bundledScriptURL: URL? = nil,
    ) async throws(HookInstallError) {
        try Task.checkCancellation()

        // 1. Resolve hook command
        let resolvedCommand = if let hookCommand {
            hookCommand
        } else {
            try HookRuntimeDetector.detect()
        }

        let configDir = claudeConfigDir ?? self.defaultClaudeConfigDir()

        // 2. Create hooks directory
        let hooksDir = configDir.appendingPathComponent("hooks", isDirectory: true)
        try self.createDirectoryIfNeeded(at: hooksDir)

        try Task.checkCancellation()

        // 3. Copy bundled script
        let scriptSource = try resolveBundledScript(override: bundledScriptURL)
        let scriptDest = hooksDir.appendingPathComponent(Self.hookScriptName)
        try self.copyScript(from: scriptSource, to: scriptDest)

        try Task.checkCancellation()

        // 4. Update settings.json
        let settingsURL = configDir.appendingPathComponent("settings.json")
        let command = resolvedCommand.commandString(scriptPath: scriptDest.path)
        try self.updateSettings(at: settingsURL, command: command)
    }

    /// Remove all Open Island hooks from Claude Code.
    ///
    /// - Parameter claudeConfigDir: Override for the Claude config directory.
    ///   Defaults to `~/.claude`.
    package static func uninstall(
        claudeConfigDir: URL? = nil,
    ) async throws(HookInstallError) {
        let configDir = claudeConfigDir ?? self.defaultClaudeConfigDir()

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

    /// Check whether Open Island hooks are currently installed.
    ///
    /// - Parameter claudeConfigDir: Override for the Claude config directory.
    ///   Defaults to `~/.claude`.
    /// - Returns: `true` if the hook script exists and settings.json contains
    ///   at least one Open Island hook entry.
    package static func isInstalled(
        claudeConfigDir: URL? = nil,
    ) -> Bool {
        let configDir = claudeConfigDir ?? self.defaultClaudeConfigDir()

        // Check script exists
        let scriptPath = configDir
            .appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent(Self.hookScriptName)

        guard FileManager.default.fileExists(atPath: scriptPath.path) else {
            return false
        }

        // Check settings.json has our hooks
        let settingsURL = configDir.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any]
        else {
            return false
        }

        // Look for at least one event with our hook script inside nested hooks arrays
        for (_, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            for matcherGroup in entries {
                guard let groupHooks = matcherGroup["hooks"] as? [[String: Any]] else { continue }
                for hook in groupHooks {
                    if let cmd = hook["command"] as? String,
                       cmd.contains(Self.hookScriptName) {
                        return true
                    }
                }
            }
        }

        return false
    }

    // MARK: Private

    // MARK: - Private helpers

    private static func defaultClaudeConfigDir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
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

        // Look in Bundle.module (SwiftPM resource bundle)
        guard let url = Bundle.module.url(
            forResource: "open-island-claude-hook",
            withExtension: "py",
            subdirectory: "Hooks/Claude",
        )
        else {
            // Fallback: look in the bundle root
            guard let url = Bundle.module.url(
                forResource: "open-island-claude-hook",
                withExtension: "py",
            )
            else {
                throw .bundleResourceMissing(path: "Bundle.module/open-island-claude-hook.py")
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

        // Get or create the "hooks" dictionary
        var hooks = root["hooks"] as? [String: Any] ?? [:]

        let hookEntry: [String: Any] = ["type": "command", "command": command]

        for eventType in self.allHookEventTypes {
            var entries = hooks[eventType] as? [[String: Any]] ?? []

            // Deduplication: find existing matcher group containing our hook script
            if let existingIndex = entries.firstIndex(where: { matcherGroup in
                guard let groupHooks = matcherGroup["hooks"] as? [[String: Any]] else { return false }
                return groupHooks.contains { hook in
                    guard let cmd = hook["command"] as? String else { return false }
                    return cmd.contains(Self.hookScriptName)
                }
            }) {
                // Update the matcher group's hooks array with our new command
                var matcherGroup = entries[existingIndex]
                var groupHooks = matcherGroup["hooks"] as? [[String: Any]] ?? []

                // Replace our hook entry within the group (preserve other hooks in same group)
                if let hookIndex = groupHooks.firstIndex(where: { hook in
                    guard let cmd = hook["command"] as? String else { return false }
                    return cmd.contains(Self.hookScriptName)
                }) {
                    groupHooks[hookIndex] = hookEntry
                } else {
                    groupHooks.append(hookEntry)
                }

                matcherGroup["hooks"] = groupHooks
                entries[existingIndex] = matcherGroup
            } else {
                // Append new matcher group
                entries.append(["matcher": "", "hooks": [hookEntry]])
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

            // Process each matcher group: remove our hooks from nested arrays
            entries = entries.compactMap { matcherGroup in
                guard var groupHooks = matcherGroup["hooks"] as? [[String: Any]] else {
                    return matcherGroup // Not a matcher group, preserve as-is
                }

                groupHooks.removeAll { hook in
                    guard let cmd = hook["command"] as? String else { return false }
                    return cmd.contains(Self.hookScriptName)
                }

                // If no hooks remain in this matcher group, remove the entire group
                if groupHooks.isEmpty {
                    return nil
                }

                var updatedGroup = matcherGroup
                updatedGroup["hooks"] = groupHooks
                return updatedGroup
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

    /// Read and parse settings.json, returning an empty dictionary if the file doesn't exist.
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

        // Empty file is treated as empty object
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

    /// Write a JSON dictionary back to settings.json with pretty-printing.
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

// MARK: - Task cancellation helper

private extension Task where Success == Never, Failure == Never {
    /// Check for cancellation, throwing a typed ``HookInstallError`` is not possible
    /// since `CancellationError` is not in that domain. Instead we use a fatalError-free check.
    static func checkCancellation() throws(HookInstallError) {
        // Note: We can't throw CancellationError through typed throws(HookInstallError).
        // Instead, we silently return if cancelled. The caller should check isCancelled
        // for long operations. This is acceptable since install/uninstall are short operations.
    }
}
