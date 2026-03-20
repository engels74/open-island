import Foundation
@testable import OIProviders
import Testing

// MARK: - GeminiHookInstallerTestHelpers

/// Shared helpers for Gemini hook installer tests.
private enum GeminiHookInstallerTestHelpers {
    /// Create a temporary directory simulating `~/.gemini/`.
    static func makeTempGeminiDir() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OITest-gemini-\(UUID().uuidString)", isDirectory: true)
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
        let scriptURL = scriptsDir.appendingPathComponent(GeminiHookInstaller.hookScriptName)
        try Data("#!/usr/bin/env python3\nprint('test')\n".utf8).write(to: scriptURL)
        return scriptURL
    }

    /// Clean up temp directory.
    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - GeminiHookInstallerInstallTests

@Suite(.tags(.gemini), .serialized)
struct GeminiHookInstallerInstallTests {
    @Test
    func `install writes settings json with all 11 event types`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)

        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        let hooks = try #require(json["hooks"] as? [String: Any])

        #expect(hooks.count == 11)

        for eventType in GeminiHookInstaller.allHookEventTypes {
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
            #expect(command.contains(GeminiHookInstaller.hookScriptName))
        }
    }

    @Test
    func `install copies script to hooks directory`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)

        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let destPath = tempDir
            .appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent(GeminiHookInstaller.hookScriptName)

        #expect(FileManager.default.fileExists(atPath: destPath.path))
    }

    @Test
    func `install creates hooks directory if missing`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)

        let hooksDir = tempDir.appendingPathComponent("hooks", isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: hooksDir.path))

        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        #expect(FileManager.default.fileExists(atPath: hooksDir.path))
    }

    @Test
    func `install twice does not duplicate hooks`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)

        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )
        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        let hooks = try #require(json["hooks"] as? [String: Any])

        for eventType in GeminiHookInstaller.allHookEventTypes {
            let entries = try #require(hooks[eventType] as? [[String: Any]])
            #expect(entries.count == 1, "Event \(eventType) should have exactly 1 matcher group")
            let groupHooks = try #require(entries[0]["hooks"] as? [[String: Any]])
            #expect(groupHooks.count == 1, "Event \(eventType) should have exactly 1 hook")
        }
    }

    @Test
    func `install updates hook command on reinstall`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)

        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )
        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/local/bin/python3"),
            geminiConfigDir: tempDir,
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
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let existingJSON: [String: Any] = [
            "theme": "dark",
            "model": "gemini-2.5-pro",
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existingJSON)
        try existingData.write(to: settingsURL)

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )

        #expect(json["theme"] as? String == "dark")
        #expect(json["model"] as? String == "gemini-2.5-pro")
        #expect(json["hooks"] != nil)
    }

    @Test
    func `install preserves existing third party hooks`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let existingJSON: [String: Any] = [
            "hooks": [
                "AfterTool": [
                    [
                        "matcher": "shell",
                        "hooks": [
                            ["type": "command", "command": "/usr/local/bin/some-other-tool"],
                        ],
                    ] as [String: Any],
                ],
            ],
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existingJSON)
        try existingData.write(to: settingsURL)

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        let hooks = try #require(json["hooks"] as? [String: Any])
        let afterToolEntries = try #require(hooks["AfterTool"] as? [[String: Any]])

        // Should have 2 matcher groups: third-party + ours
        #expect(afterToolEntries.count == 2)

        // Verify third-party matcher group preserved
        let thirdPartyGroup = try #require(
            afterToolEntries.first { $0["matcher"] as? String == "shell" },
        )
        let thirdPartyHooks = try #require(thirdPartyGroup["hooks"] as? [[String: Any]])
        #expect(thirdPartyHooks[0]["command"] as? String == "/usr/local/bin/some-other-tool")

        // Verify our matcher group exists
        let ourGroup = try #require(
            afterToolEntries.first { matcherGroup in
                guard let groupHooks = matcherGroup["hooks"] as? [[String: Any]] else { return false }
                return groupHooks.contains {
                    ($0["command"] as? String)?.contains(GeminiHookInstaller.hookScriptName) == true
                }
            },
        )
        let ourHooks = try #require(ourGroup["hooks"] as? [[String: Any]])
        #expect(ourHooks.count == 1)
    }
}

// MARK: - GeminiHookInstallerUninstallTests

@Suite(.tags(.gemini), .serialized)
struct GeminiHookInstallerUninstallTests {
    @Test
    func `uninstall removes hook script`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        try await GeminiHookInstaller.uninstall(geminiConfigDir: tempDir)

        let destPath = tempDir
            .appendingPathComponent("hooks", isDirectory: true)
            .appendingPathComponent(GeminiHookInstaller.hookScriptName)

        #expect(!FileManager.default.fileExists(atPath: destPath.path))
    }

    @Test
    func `uninstall removes hook entries from settings`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        try await GeminiHookInstaller.uninstall(geminiConfigDir: tempDir)

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )

        #expect(json["hooks"] == nil)
    }

    @Test
    func `uninstall preserves third party hooks`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        // Manually add a third-party hook in nested format
        let settingsURL = tempDir.appendingPathComponent("settings.json")
        var data = try Data(contentsOf: settingsURL)
        var json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        var hooks = json["hooks"] as? [String: Any] ?? [:]
        var beforeToolEntries = hooks["BeforeTool"] as? [[String: Any]] ?? []
        beforeToolEntries.append([
            "matcher": "",
            "hooks": [["type": "command", "command": "/usr/local/bin/other-tool"]],
        ] as [String: Any])
        hooks["BeforeTool"] = beforeToolEntries
        json["hooks"] = hooks
        data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        try data.write(to: settingsURL)

        try await GeminiHookInstaller.uninstall(geminiConfigDir: tempDir)

        data = try Data(contentsOf: settingsURL)
        json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        hooks = try #require(json["hooks"] as? [String: Any])
        let remaining = try #require(hooks["BeforeTool"] as? [[String: Any]])

        #expect(remaining.count == 1)
        let remainingHooks = try #require(remaining[0]["hooks"] as? [[String: Any]])
        #expect(remainingHooks[0]["command"] as? String == "/usr/local/bin/other-tool")
    }

    @Test
    func `uninstall on clean directory does not throw`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        try await GeminiHookInstaller.uninstall(geminiConfigDir: tempDir)
    }
}

// MARK: - GeminiHookInstallerIsInstalledTests

@Suite(.tags(.gemini), .serialized)
struct GeminiHookInstallerIsInstalledTests {
    @Test
    func `isInstalled returns false before install`() throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        #expect(!GeminiHookInstaller.isInstalled(geminiConfigDir: tempDir))
    }

    @Test
    func `isInstalled returns true after install`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        #expect(GeminiHookInstaller.isInstalled(geminiConfigDir: tempDir))
    }

    @Test
    func `isInstalled returns false after uninstall`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )
        try await GeminiHookInstaller.uninstall(geminiConfigDir: tempDir)

        #expect(!GeminiHookInstaller.isInstalled(geminiConfigDir: tempDir))
    }
}

// MARK: - GeminiHookInstallerEdgeCaseTests

@Suite(.tags(.gemini), .serialized)
struct GeminiHookInstallerEdgeCaseTests {
    @Test
    func `install throws settingsFileCorrupted for invalid json`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        try Data("not valid json{{{".utf8).write(to: settingsURL)

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)

        await #expect(throws: HookInstallError.self) {
            try await GeminiHookInstaller.install(
                hookCommand: .python(path: "/usr/bin/python3"),
                geminiConfigDir: tempDir,
                bundledScriptURL: scriptURL,
            )
        }
    }

    @Test
    func `settings json with empty file is treated as empty object`() async throws {
        let tempDir = try GeminiHookInstallerTestHelpers.makeTempGeminiDir()
        defer { GeminiHookInstallerTestHelpers.cleanup(tempDir) }

        let settingsURL = tempDir.appendingPathComponent("settings.json")
        try Data().write(to: settingsURL)

        let scriptURL = try GeminiHookInstallerTestHelpers.createFakeScript(in: tempDir)
        try await GeminiHookInstaller.install(
            hookCommand: .python(path: "/usr/bin/python3"),
            geminiConfigDir: tempDir,
            bundledScriptURL: scriptURL,
        )

        let data = try Data(contentsOf: settingsURL)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        #expect(json["hooks"] != nil)
    }
}
