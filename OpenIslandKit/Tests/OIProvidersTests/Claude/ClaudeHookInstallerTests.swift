import Foundation
@testable import OIProviders
import Testing

// MARK: - HookInstallerTestHelpers

/// Shared helpers for hook installer tests.
private enum HookInstallerTestHelpers {
    /// Create a temporary directory simulating `~/.claude/`.
    static func makeTempClaudeDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OITest-claude-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true,
        )
        return tempDir
    }

    /// Create a fake Python script file to use as the bundled source.
    static func createFakeScript(in dir: URL) throws -> URL {
        let scriptsDir = dir.appendingPathComponent("bundled", isDirectory: true)
        try FileManager.default.createDirectory(
            at: scriptsDir,
            withIntermediateDirectories: true,
        )
        let scriptURL = scriptsDir.appendingPathComponent(ClaudeHookInstaller.hookScriptName)
        try Data("#!/usr/bin/env python3\nprint('test')\n".utf8).write(to: scriptURL)
        return scriptURL
    }

    /// Clean up temp directory.
    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - ClaudeHookInstallerInstallTests

@Suite(.tags(.claude), .serialized)
struct ClaudeHookInstallerInstallTests {
    @Test
    func `install writes settings json with all 17 event types`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)

        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        let hooks = try #require(json["hooks"] as? [String: Any])

        #expect(hooks.count == 17)
        #expect(hooks["PreToolUse"] == nil)

        for eventType in ClaudeHookInstaller.allHookEventTypes {
            let entries = try #require(hooks[eventType] as? [[String: Any]])
            #expect(entries.count == 1)
            let matcherGroup = entries[0]
            let matcher = try #require(matcherGroup["matcher"] as? String)
            #expect(matcher.isEmpty)
            let groupHooks = try #require(matcherGroup["hooks"] as? [[String: Any]])
            #expect(groupHooks.count == 1)
            #expect(groupHooks[0]["type"] as? String == "command")
            let command = try #require(groupHooks[0]["command"] as? String)
            #expect(command.contains("python3"))
            #expect(command.contains(ClaudeHookInstaller.hookScriptName))
        }
    }

    @Test
    func `install copies script to hooks directory`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)

        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let destPath = tempDir
            .appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent(ClaudeHookInstaller.hookScriptName)

        #expect(FileManager.default.fileExists(atPath: destPath.path))
    }

    @Test
    func `install creates hooks directory if missing`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)

        let hooksDir = tempDir.appendingPathComponent("hooks", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: hooksDir.path))

        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        #expect(FileManager.default.fileExists(atPath: hooksDir.path))
    }

    @Test
    func `install twice does not duplicate hooks`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)

        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )
        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        let hooks = try #require(json["hooks"] as? [String: Any])

        for eventType in ClaudeHookInstaller.allHookEventTypes {
            let entries = try #require(hooks[eventType] as? [[String: Any]])
            #expect(entries.count == 1, "Event \(eventType) should have exactly 1 matcher group")
            let groupHooks = try #require(entries[0]["hooks"] as? [[String: Any]])
            #expect(groupHooks.count == 1, "Event \(eventType) should have exactly 1 hook")
        }
    }

    @Test
    func `install updates hook command on reinstall`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)

        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )
        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/local/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        let hooks = try #require(json["hooks"] as? [String: Any])
        let entries = try #require(hooks["SessionStart"] as? [[String: Any]])
        let groupHooks = try #require(entries[0]["hooks"] as? [[String: Any]])
        let command = try #require(groupHooks[0]["command"] as? String)

        #expect(command.contains("/usr/local/bin/python3"))
        #expect(!command.contains("/usr/bin/python3"))
    }

    @Test
    func `install preserves existing settings`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let existingJSON: [String: Any] = [
            "theme": "dark",
            "model": "claude-sonnet-4-5-20250929",
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existingJSON)
        try existingData.write(to: settingsURL)

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )

        #expect(json["theme"] as? String == "dark")
        #expect(json["model"] as? String == "claude-sonnet-4-5-20250929")
        #expect(json["hooks"] != nil)
    }

    @Test
    func `install preserves existing third party hooks`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let existingJSON: [String: Any] = [
            "hooks": [
                "PostToolUse": [
                    [
                        "matcher": "Bash",
                        "hooks": [
                            ["type": "command", "command": "/usr/local/bin/some-other-tool"],
                        ],
                    ] as [String: Any],
                ],
            ],
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existingJSON)
        try existingData.write(to: settingsURL)

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        let hooks = try #require(json["hooks"] as? [String: Any])
        let postToolEntries = try #require(hooks["PostToolUse"] as? [[String: Any]])

        #expect(postToolEntries.count == 2)

        let thirdPartyGroup = try #require(
            postToolEntries.first { $0["matcher"] as? String == "Bash" },
        )
        let thirdPartyHooks = try #require(thirdPartyGroup["hooks"] as? [[String: Any]])
        #expect(thirdPartyHooks[0]["command"] as? String == "/usr/local/bin/some-other-tool")

        let ourGroup = try #require(
            postToolEntries.first { matcherGroup in
                guard let groupHooks = matcherGroup["hooks"] as? [[String: Any]] else { return false }
                return groupHooks.contains { ($0["command"] as? String)?.contains(ClaudeHookInstaller.hookScriptName) == true }
            },
        )
        let ourHooks = try #require(ourGroup["hooks"] as? [[String: Any]])
        #expect(ourHooks.count == 1)
    }
}

// MARK: - ClaudeHookInstallerUninstallTests

@Suite(.tags(.claude), .serialized)
struct ClaudeHookInstallerUninstallTests {
    @Test
    func `uninstall removes hook script`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        try await ClaudeHookInstaller.uninstall(claudeConfigDir: tempDir)

        let destPath = tempDir
            .appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent(ClaudeHookInstaller.hookScriptName)

        #expect(!FileManager.default.fileExists(atPath: destPath.path))
    }

    @Test
    func `uninstall removes hook entries from settings`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        try await ClaudeHookInstaller.uninstall(claudeConfigDir: tempDir)

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )

        #expect(json["hooks"] == nil)
    }

    @Test
    func `uninstall preserves third party hooks`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        var data = try Data(contentsOf: settingsURL)
        var json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        var hooks = json["hooks"] as? [String: Any] ?? [:]
        var preToolEntries = hooks["PreToolUse"] as? [[String: Any]] ?? []
        preToolEntries.append([
            "matcher": "",
            "hooks": [["type": "command", "command": "/usr/local/bin/other-tool"]],
        ] as [String: Any])
        hooks["PreToolUse"] = preToolEntries
        json["hooks"] = hooks
        data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        try data.write(to: settingsURL)

        try await ClaudeHookInstaller.uninstall(claudeConfigDir: tempDir)

        data = try Data(contentsOf: settingsURL)
        json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        hooks = try #require(json["hooks"] as? [String: Any])
        let remaining = try #require(hooks["PreToolUse"] as? [[String: Any]])

        #expect(remaining.count == 1)
        let remainingHooks = try #require(remaining[0]["hooks"] as? [[String: Any]])
        #expect(remainingHooks[0]["command"] as? String == "/usr/local/bin/other-tool")
    }

    @Test
    func `uninstall on clean directory does not throw`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        try await ClaudeHookInstaller.uninstall(claudeConfigDir: tempDir)
    }

    @Test
    func `isInstalled returns false before install`() throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        #expect(!ClaudeHookInstaller.isInstalled(claudeConfigDir: tempDir))
    }

    @Test
    func `isInstalled returns true after install`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        #expect(ClaudeHookInstaller.isInstalled(claudeConfigDir: tempDir))
    }

    @Test
    func `isInstalled returns false after uninstall`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )
        try await ClaudeHookInstaller.uninstall(claudeConfigDir: tempDir)

        #expect(!ClaudeHookInstaller.isInstalled(claudeConfigDir: tempDir))
    }

    @Test
    func `install throws settingsFileCorrupted for invalid json`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        try Data("not valid json{{{".utf8).write(to: settingsURL)

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)

        await #expect(throws: HookInstallError.self) {
            try await ClaudeHookInstaller.install(
                hookCommand: .python(path: "/usr/bin/python3"),
                claudeConfigDir: tempDir,
                bundledScriptURL: scriptURL,
            )
        }
    }

    @Test
    func `settings json with empty file is treated as empty object`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        try Data().write(to: settingsURL)

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await ClaudeHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        #expect(json["hooks"] != nil)
    }
}

// MARK: - HookRuntimeDetectorTests

@Suite(.tags(.claude))
struct HookRuntimeDetectorTests {
    // MARK: Internal

    @Test(.enabled(if: hasCompatibleRuntime))
    func `detect returns a valid hook command`() throws {
        let command = try HookRuntimeDetector.detect()
        switch command {
        case let .uv(path):
            #expect(!path.isEmpty)
        case let .python(path):
            #expect(!path.isEmpty)
            #expect(path.contains("python"))
        }
    }

    // MARK: Private

    /// Whether `uv` or Python 3.14+ is available on this machine.
    private static let hasCompatibleRuntime: Bool = (try? HookRuntimeDetector.detect()) != nil
}

// MARK: - HookCommandTests

@Suite(.tags(.claude))
struct HookCommandTests {
    @Test
    func `uv commandString produces uv run command`() {
        let command = HookCommand.uv(path: "/usr/local/bin/uv")
        let result = command.commandString(scriptPath: "/home/user/.claude/hooks/hook.py")

        #expect(result.contains("uv"))
        #expect(result.contains("run"))
        #expect(result.contains("--python"))
        #expect(result.contains(">=3.14"))
        #expect(result.contains("hook.py"))
    }

    @Test
    func `python commandString produces direct python command`() {
        let command = HookCommand.python(path: "/usr/bin/python3")
        let result = command.commandString(scriptPath: "/home/user/.claude/hooks/hook.py")

        #expect(result.contains("python3"))
        #expect(result.contains("hook.py"))
        #expect(!result.contains("uv"))
    }

    @Test
    func `commandString shell-quotes paths with spaces`() {
        let command = HookCommand.python(path: "/path with spaces/python3")
        let result = command.commandString(scriptPath: "/script path/hook.py")

        #expect(result.contains("'/path with spaces/python3'"))
        #expect(result.contains("'/script path/hook.py'"))
    }

    @Test
    func `commandString shell-quotes paths with single quotes`() {
        let command = HookCommand.python(path: "/path'quoted/python3")
        let result = command.commandString(scriptPath: "/script/hook.py")

        #expect(result.contains("'\\''"))
    }
}
