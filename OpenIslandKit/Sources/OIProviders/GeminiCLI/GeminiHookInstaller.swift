package import Foundation

// MARK: - GeminiHookInstaller

/// Installs and manages the Open Island hook script for Gemini CLI.
package struct GeminiHookInstaller: Sendable {
    // MARK: Package

    package static let allHookEventTypes: [String] = [
        "SessionStart", "SessionEnd",
        "BeforeAgent", "AfterAgent",
        "BeforeModel", "AfterModel",
        "BeforeToolSelection",
        "BeforeTool", "AfterTool",
        "PreCompress",
        "Notification",
    ]

    package static let hookScriptName = "open-island-gemini-hook.py"

    package static func install(
        hookCommand: HookCommand? = nil,
        geminiConfigDir: URL? = nil,
        bundledScriptURL: URL? = nil,
    ) async throws(HookInstallError) {
        let resolvedCommand = if let hookCommand {
            hookCommand
        } else {
            try HookRuntimeDetector.detect()
        }

        let configDir = geminiConfigDir ?? self.defaultGeminiConfigDir()

        let hooksDir = configDir.appendingPathComponent("hooks", isDirectory: true)
        try self.createDirectoryIfNeeded(at: hooksDir)

        let scriptSource = try resolveBundledScript(override: bundledScriptURL)
        let scriptDest = hooksDir.appendingPathComponent(Self.hookScriptName)
        try self.copyScript(from: scriptSource, to: scriptDest)

        let settingsURL = configDir.appendingPathComponent("settings.json")
        let command = resolvedCommand.commandString(scriptPath: scriptDest.path)
        try self.updateSettings(at: settingsURL, command: command)
    }

    package static func uninstall(
        geminiConfigDir: URL? = nil,
    ) async throws(HookInstallError) {
        let configDir = geminiConfigDir ?? self.defaultGeminiConfigDir()

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

        let settingsURL = configDir.appendingPathComponent("settings.json")
        try self.removeHooksFromSettings(at: settingsURL)
    }

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

    private static func updateSettings(
        at settingsURL: URL,
        command: String,
    ) throws(HookInstallError) {
        var root = try readSettingsJSON(at: settingsURL)

        var hooks = root["hooks"] as? [String: Any] ?? [:]

        let hookEntry: [String: Any] = ["type": "command", "command": command]

        for eventType in self.allHookEventTypes {
            var entries = hooks[eventType] as? [[String: Any]] ?? []

            if let existingIndex = entries.firstIndex(where: { matcherGroup in
                guard let groupHooks = matcherGroup["hooks"] as? [[String: Any]] else { return false }
                return groupHooks.contains { hook in
                    guard let cmd = hook["command"] as? String else { return false }
                    return cmd.contains(Self.hookScriptName)
                }
            }) {
                var matcherGroup = entries[existingIndex]
                var groupHooks = matcherGroup["hooks"] as? [[String: Any]] ?? []

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
                entries.append(["matcher": "", "hooks": [hookEntry]])
            }

            hooks[eventType] = entries
        }

        root["hooks"] = hooks
        try self.writeSettingsJSON(root, to: settingsURL)
    }

    private static func removeHooksFromSettings(
        at settingsURL: URL,
    ) throws(HookInstallError) {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }

        var root = try readSettingsJSON(at: settingsURL)

        guard var hooks = root["hooks"] as? [String: Any] else { return }

        for eventType in self.allHookEventTypes {
            guard var entries = hooks[eventType] as? [[String: Any]] else { continue }

            entries = entries.compactMap { matcherGroup in
                // Legacy flat entry (pre-matcher-group format)
                if matcherGroup["hooks"] == nil,
                   let cmd = matcherGroup["command"] as? String,
                   cmd.contains(Self.hookScriptName) {
                    return nil
                }

                guard var groupHooks = matcherGroup["hooks"] as? [[String: Any]] else {
                    return matcherGroup // Not a matcher group and not our legacy entry, preserve as-is
                }

                groupHooks.removeAll { hook in
                    guard let cmd = hook["command"] as? String else { return false }
                    return cmd.contains(Self.hookScriptName)
                }

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
