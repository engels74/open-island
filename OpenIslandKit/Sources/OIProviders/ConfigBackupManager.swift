public import Foundation
public import OICore
import OSLog

private let logger = Logger(subsystem: "com.engels74.openisland", category: "ConfigBackup")

// MARK: - BackupEntry

package struct BackupEntry: Sendable {
    package let originalPath: String
    package let backupURL: URL
    package let date: Date
}

// MARK: - ConfigBackupError

public enum ConfigBackupError: Error, Sendable {
    case backupDirectoryCreationFailed(path: String)
    case sourceFileNotFound(path: String)
    case backupCopyFailed(source: String, destination: String)
    case restoreSourceNotFound(backupURL: URL)
    case restoreFailed(from: URL, to: String)
}

// MARK: CustomStringConvertible

extension ConfigBackupError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .backupDirectoryCreationFailed(path):
            "Could not create backup directory: \(path)"
        case let .sourceFileNotFound(path):
            "Config file not found: \(path)"
        case let .backupCopyFailed(source, destination):
            "Failed to copy \(source) to \(destination)"
        case let .restoreSourceNotFound(backupURL):
            "Backup file not found: \(backupURL.path)"
        case let .restoreFailed(from, to):
            "Failed to restore \(from.path) to \(to)"
        }
    }
}

// MARK: - ConfigBackupManager

/// Backups stored at `~/.open-island/backups/{provider}/{timestamp}/`.
package struct ConfigBackupManager: Sendable {
    // MARK: Lifecycle

    package init(backupsBaseURL: URL? = nil) {
        self.backupsBaseURL = backupsBaseURL ?? Self.defaultBackupsBaseURL()
    }

    // MARK: Package

    package let backupsBaseURL: URL

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

    package func restoreBackup(
        from backupURL: URL,
        to destinationPath: String,
    ) throws(ConfigBackupError) {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw .restoreSourceNotFound(backupURL: backupURL)
        }

        let destinationURL = URL(fileURLWithPath: destinationPath)

        do {
            if FileManager.default.fileExists(atPath: destinationPath) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: backupURL, to: destinationURL)
        } catch {
            throw .restoreFailed(from: backupURL, to: destinationPath)
        }
    }

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

            let date = Self.timestampFormatter.date(from: dir.lastPathComponent) ?? Date.distantPast

            for file in files where file.pathExtension != "origin" {
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
