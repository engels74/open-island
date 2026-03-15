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
    func `install writes settings json with all 18 event types`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)

        try await ClaudeHookInstaller.install(
            pythonPath: "/usr/bin/python3",
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        let hooks = try #require(json["hooks"] as? [String: Any])

        #expect(hooks.count == 18)

        for eventType in ClaudeHookInstaller.allHookEventTypes {
            let entries = try #require(hooks[eventType] as? [[String: Any]])
            #expect(entries.count == 1)
            let entry = entries[0]
            #expect(entry["type"] as? String == "command")
            let command = try #require(entry["command"] as? String)
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
            pythonPath: "/usr/bin/python3",
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
            pythonPath: "/usr/bin/python3",
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
            pythonPath: "/usr/bin/python3",
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )
        try await ClaudeHookInstaller.install(
            pythonPath: "/usr/bin/python3",
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
            #expect(entries.count == 1, "Event \(eventType) should have exactly 1 entry")
        }
    }

    @Test
    func `install updates python path on reinstall`() async throws {
        let tempDir = try HookInstallerTestHelpers.makeTempClaudeDir()
        defer { HookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)

        try await ClaudeHookInstaller.install(
            pythonPath: "/usr/bin/python3",
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )
        try await ClaudeHookInstaller.install(
            pythonPath: "/usr/local/bin/python3",
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
        let command = try #require(entries[0]["command"] as? String)

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
            pythonPath: "/usr/bin/python3",
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
                "PreToolUse": [
                    ["type": "command", "command": "/usr/local/bin/some-other-tool"],
                ],
            ],
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existingJSON)
        try existingData.write(to: settingsURL)

        let scriptURL = try HookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await ClaudeHookInstaller.install(
            pythonPath: "/usr/bin/python3",
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        let hooks = try #require(json["hooks"] as? [String: Any])
        let preToolEntries = try #require(hooks["PreToolUse"] as? [[String: Any]])

        #expect(preToolEntries.count == 2)

        let commands = preToolEntries.compactMap { $0["command"] as? String }
        #expect(commands.contains("/usr/local/bin/some-other-tool"))
        #expect(commands.contains { $0.contains(ClaudeHookInstaller.hookScriptName) })
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
            pythonPath: "/usr/bin/python3",
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
            pythonPath: "/usr/bin/python3",
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
            pythonPath: "/usr/bin/python3",
            claudeConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        // Manually add a third-party hook
        let settingsURL = tempDir.appendingPathComponent("settings.json")
        var data = try Data(contentsOf: settingsURL)
        var json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        var hooks = json["hooks"] as? [String: Any] ?? [:]
        var preToolEntries = hooks["PreToolUse"] as? [[String: Any]] ?? []
        preToolEntries.append(["type": "command", "command": "/usr/local/bin/other-tool"])
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
        #expect(remaining[0]["command"] as? String == "/usr/local/bin/other-tool")
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
            pythonPath: "/usr/bin/python3",
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
            pythonPath: "/usr/bin/python3",
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
                pythonPath: "/usr/bin/python3",
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
            pythonPath: "/usr/bin/python3",
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

// MARK: - PythonRuntimeDetectorTests

@Suite(.tags(.claude))
struct PythonRuntimeDetectorTests {
    @Test
    func `detect finds python3`() throws {
        let path = try PythonRuntimeDetector.detect()
        #expect(!path.isEmpty)
        #expect(path.contains("python"))
    }
}
