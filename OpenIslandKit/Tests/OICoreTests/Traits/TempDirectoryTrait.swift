import Foundation
import Synchronization
import Testing

// MARK: - TempDirectoryTrait

/// A test trait that creates a unique temporary directory before the test
/// and cleans it up after the test completes.
///
/// Usage: Apply `.tempDirectory` to a `@Suite` or `@Test`. Access the
/// directory URL via `TempDirectoryTrait.url` inside the test body.
struct TempDirectoryTrait: SuiteTrait, TestScoping {
    // MARK: Internal

    /// The temporary directory URL for the current test scope.
    static var url: URL {
        get throws {
            guard let value = _currentURL.withLock({ $0 }) else {
                throw TempDirectoryError.notInScope
            }
            return value
        }
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void,
    ) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OICoreTests-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        Self._currentURL.withLock { $0 = tempDir }
        defer {
            Self._currentURL.withLock { $0 = nil }
            try? FileManager.default.removeItem(at: tempDir)
        }

        try await function()
    }

    // MARK: Private

    private static let _currentURL = Mutex<URL?>(nil)
}

// MARK: - TempDirectoryError

enum TempDirectoryError: Error, CustomStringConvertible {
    case notInScope

    // MARK: Internal

    var description: String {
        "TempDirectoryTrait.url accessed outside of a test annotated with .tempDirectory"
    }
}

extension SuiteTrait where Self == TempDirectoryTrait {
    /// Provides a unique temporary directory for the duration of the test.
    static var tempDirectory: Self {
        TempDirectoryTrait()
    }
}
