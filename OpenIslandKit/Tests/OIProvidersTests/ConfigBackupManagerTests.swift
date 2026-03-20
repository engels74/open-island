import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - ConfigBackupManagerTests

struct ConfigBackupManagerTests {
    // MARK: Internal

    @Test
    func `creates backup in correct directory structure`() throws {
        try self.withTempDir { tempDir in
            let backupsDir = tempDir.appendingPathComponent("backups", isDirectory: true)
            let manager = ConfigBackupManager(backupsBaseURL: backupsDir)

            // Create a source file to back up
            let sourceFile = tempDir.appendingPathComponent("settings.json")
            try Data("{\"hooks\": {}}".utf8).write(to: sourceFile)

            let backupURL = try manager.createBackup(for: sourceFile.path, provider: .claude)

            // Backup should exist
            #expect(FileManager.default.fileExists(atPath: backupURL.path))

            // Backup should be under backups/claude/{timestamp}/settings.json
            #expect(backupURL.pathComponents.contains("claude"))
            #expect(backupURL.lastPathComponent == "settings.json")

            // Content should match
            let backupContent = try String(contentsOf: backupURL, encoding: .utf8)
            #expect(backupContent == "{\"hooks\": {}}")
        }
    }

    @Test
    func `restores backup to original path`() throws {
        try self.withTempDir { tempDir in
            let backupsDir = tempDir.appendingPathComponent("backups", isDirectory: true)
            let manager = ConfigBackupManager(backupsBaseURL: backupsDir)

            // Create source, back it up, then delete original
            let sourceFile = tempDir.appendingPathComponent("config.json")
            let originalContent = "{\"original\": true}"
            try Data(originalContent.utf8).write(to: sourceFile)

            let backupURL = try manager.createBackup(for: sourceFile.path, provider: .codex)
            try FileManager.default.removeItem(at: sourceFile)
            #expect(!FileManager.default.fileExists(atPath: sourceFile.path))

            // Restore
            try manager.restoreBackup(from: backupURL, to: sourceFile.path)
            #expect(FileManager.default.fileExists(atPath: sourceFile.path))

            let restored = try String(contentsOf: sourceFile, encoding: .utf8)
            #expect(restored == originalContent)
        }
    }

    @Test
    func `restore overwrites existing file`() throws {
        try self.withTempDir { tempDir in
            let backupsDir = tempDir.appendingPathComponent("backups", isDirectory: true)
            let manager = ConfigBackupManager(backupsBaseURL: backupsDir)

            let sourceFile = tempDir.appendingPathComponent("settings.json")
            try Data("{\"version\": 1}".utf8).write(to: sourceFile)

            let backupURL = try manager.createBackup(for: sourceFile.path, provider: .claude)

            // Overwrite the original with different content
            try Data("{\"version\": 2}".utf8).write(to: sourceFile)

            // Restore should bring back version 1
            try manager.restoreBackup(from: backupURL, to: sourceFile.path)
            let content = try String(contentsOf: sourceFile, encoding: .utf8)
            #expect(content == "{\"version\": 1}")
        }
    }

    @Test
    func `lists backups for provider`() throws {
        try self.withTempDir { tempDir in
            let backupsDir = tempDir.appendingPathComponent("backups", isDirectory: true)
            let manager = ConfigBackupManager(backupsBaseURL: backupsDir)

            let sourceFile = tempDir.appendingPathComponent("settings.json")
            try Data("content".utf8).write(to: sourceFile)

            // Create two backups
            _ = try manager.createBackup(for: sourceFile.path, provider: .claude)
            // Small delay to ensure different timestamps
            Thread.sleep(forTimeInterval: 1.1)
            _ = try manager.createBackup(for: sourceFile.path, provider: .claude)

            let backups = manager.listBackups(for: .claude)
            #expect(backups.count == 2)

            // Should be sorted newest first
            #expect(backups[0].date >= backups[1].date)
        }
    }

    @Test
    func `lists no backups for provider without any`() throws {
        try self.withTempDir { tempDir in
            let backupsDir = tempDir.appendingPathComponent("backups", isDirectory: true)
            let manager = ConfigBackupManager(backupsBaseURL: backupsDir)

            let backups = manager.listBackups(for: .geminiCLI)
            #expect(backups.isEmpty)
        }
    }

    @Test
    func `throws sourceFileNotFound for missing file`() throws {
        try self.withTempDir { tempDir in
            let backupsDir = tempDir.appendingPathComponent("backups", isDirectory: true)
            let manager = ConfigBackupManager(backupsBaseURL: backupsDir)

            let nonexistent = tempDir.appendingPathComponent("nonexistent.json").path

            #expect(throws: ConfigBackupError.self) {
                try manager.createBackup(for: nonexistent, provider: .claude)
            }
        }
    }

    @Test
    func `throws restoreSourceNotFound for missing backup`() throws {
        try self.withTempDir { tempDir in
            let backupsDir = tempDir.appendingPathComponent("backups", isDirectory: true)
            let manager = ConfigBackupManager(backupsBaseURL: backupsDir)

            let fakeBackupURL = backupsDir.appendingPathComponent("nonexistent-backup.json")
            let destinationPath = tempDir.appendingPathComponent("dest.json").path

            #expect(throws: ConfigBackupError.self) {
                try manager.restoreBackup(from: fakeBackupURL, to: destinationPath)
            }
        }
    }

    @Test
    func `default backupsBaseURL is under home directory`() {
        let manager = ConfigBackupManager()
        let path = manager.backupsBaseURL.path
        #expect(path.contains(".open-island"))
        #expect(path.contains("backups"))
    }

    @Test
    func `backups are isolated per provider`() throws {
        try self.withTempDir { tempDir in
            let backupsDir = tempDir.appendingPathComponent("backups", isDirectory: true)
            let manager = ConfigBackupManager(backupsBaseURL: backupsDir)

            let sourceFile = tempDir.appendingPathComponent("settings.json")
            try Data("data".utf8).write(to: sourceFile)

            _ = try manager.createBackup(for: sourceFile.path, provider: .claude)
            _ = try manager.createBackup(for: sourceFile.path, provider: .codex)

            let claudeBackups = manager.listBackups(for: .claude)
            let codexBackups = manager.listBackups(for: .codex)

            #expect(claudeBackups.count == 1)
            #expect(codexBackups.count == 1)
        }
    }

    // MARK: Private

    /// Creates a unique temp directory, runs the test body, then cleans up.
    private func withTempDir(
        _ body: (URL) throws -> Void,
    ) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OIProvidersTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try body(tempDir)
    }
}
