public import Foundation
public import OICore
import OSLog

private let logger = Logger(subsystem: "com.openisland", category: "ConfigBackup")

// MARK: - BackupEntry

/// A single backup record — the original file path and where it was backed up.
package struct BackupEntry: Sendable {
    /// The original path of the file that was backed up.
    package let originalPath: String

    /// The URL where the backup copy lives.
    package let backupURL: URL

    /// When the backup was created.
    package let date: Date
}

// MARK: - ConfigBackupError

/// Errors that can occur during backup or restore operations.
public enum ConfigBackupError: Error, Sendable {
    case backupDirectoryCreationFailed(path: String)
    case sourceFileNotFound(path: String)
    case backupCopyFailed(source: String, destination: String)
    case restoreSourceNotFound(backupURL: URL)
    case restoreFailed(from: URL, to: String)
}

// MARK: - ConfigBackupManager

/// Creates and manages config file backups before hook installation modifies settings files.
///
/// Backups are stored at `~/.open-island/backups/{provider}/{timestamp}/`.
/// Each backup preserves the original filename so restoring is straightforward.
package struct ConfigBackupManager: Sendable {
    // MARK: Lifecycle

    package init(backupsBaseURL: URL? = nil) {
        self.backupsBaseURL = backupsBaseURL ?? Self.defaultBackupsBaseURL()
    }

    // MARK: Package

    /// The base directory for all backups.
    /// Defaults to `~/.open-island/backups/`.
    package let backupsBaseURL: URL

    /// Create a backup of the file at the given path.
    ///
    /// - Parameter path: The absolute path to the file to back up.
    /// - Parameter provider: The provider this backup is associated with.
    /// - Returns: The URL where the backup was stored.
    package func createBackup(
        for path: String,
        provider: ProviderID,
    ) throws(ConfigBackupError) -> URL {
        let sourceURL = URL(fileURLWithPath: path)

        guard FileManager.default.fileExists(atPath: path) else {
            throw .sourceFileNotFound(path: path)
        }

        let timestamp = Self.timestampFormatter.string(from: Date())
        let backupDir = self.backupsBaseURL
            .appendingPathComponent(provider.rawValue, isDirectory: true)
            .appendingPathComponent(timestamp, isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: backupDir,
                withIntermediateDirectories: true,
            )
        } catch {
            throw .backupDirectoryCreationFailed(path: backupDir.path)
        }

        var backupURL = backupDir.appendingPathComponent(sourceURL.lastPathComponent)

        // Avoid basename collision: if destination exists (e.g., two source paths with
        // the same filename backed up in the same second), append a counter.
        if FileManager.default.fileExists(atPath: backupURL.path) {
            let stem = backupURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            var counter = 2
            repeat {
                let uniqueName = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
                backupURL = backupDir.appendingPathComponent(uniqueName)
                counter += 1
            } while FileManager.default.fileExists(atPath: backupURL.path)
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: backupURL)
        } catch {
            throw .backupCopyFailed(source: path, destination: backupURL.path)
        }

        // Write a sidecar file recording the original absolute path so listBackups can recover it.
        let originFile = backupURL.appendingPathExtension("origin")
        do {
            try Data(path.utf8).write(to: originFile)
        } catch {
            logger
                .warning(
                    "Failed to write .origin sidecar for \(backupURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)",
                )
        }

        return backupURL
    }

    /// Restore a backup to its original location.
    ///
    /// - Parameter backupURL: The URL of the backup file.
    /// - Parameter destinationPath: The path to restore the file to.
    package func restoreBackup(
        from backupURL: URL,
        to destinationPath: String,
    ) throws(ConfigBackupError) {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw .restoreSourceNotFound(backupURL: backupURL)
        }

        let destinationURL = URL(fileURLWithPath: destinationPath)

        do {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationPath) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: backupURL, to: destinationURL)
        } catch {
            throw .restoreFailed(from: backupURL, to: destinationPath)
        }
    }

    /// List all backups for a given provider, sorted by date (newest first).
    package func listBackups(for provider: ProviderID) -> [BackupEntry] {
        let providerDir = self.backupsBaseURL
            .appendingPathComponent(provider.rawValue, isDirectory: true)

        guard let timestampDirs = try? FileManager.default.contentsOfDirectory(
            at: providerDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles],
        )
        else {
            return []
        }

        var entries: [BackupEntry] = []

        for dir in timestampDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
            )
            else {
                continue
            }

            // Parse date from directory name (timestamp format)
            let date = Self.timestampFormatter.date(from: dir.lastPathComponent) ?? Date.distantPast

            for file in files where file.pathExtension != "origin" {
                // Read the original path from the sidecar .origin file written by createBackup.
                let originFile = file.appendingPathExtension("origin")
                let originalPath = (try? String(contentsOf: originFile, encoding: .utf8)) ?? file.lastPathComponent
                entries.append(BackupEntry(
                    originalPath: originalPath,
                    backupURL: file,
                    date: date,
                ))
            }
        }

        return entries.sorted { $0.date > $1.date }
    }

    // MARK: Private

    /// Format: `20260320-143052` — filesystem-safe, sortable.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func defaultBackupsBaseURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".open-island", isDirectory: true)
            .appendingPathComponent("backups", isDirectory: true)
    }
}
