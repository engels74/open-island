import Foundation
import Synchronization
import Testing

// MARK: - MockSocketTrait

/// A test trait that creates a temporary Unix domain socket path before the test
/// and cleans it up after the test completes.
///
/// Usage: Apply `.mockSocket` to a `@Suite` or `@Test`. Access the socket
/// path via `MockSocketTrait.path` inside the test body.
struct MockSocketTrait: SuiteTrait, TestScoping {
    // MARK: Internal

    /// The Unix domain socket path for the current test scope.
    static var path: String {
        get throws {
            guard let value = _currentPath.withLock({ $0 }) else {
                throw MockSocketError.notInScope
            }
            return value
        }
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void,
    ) async throws {
        let socketDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OICoreTests-sock-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: socketDir, withIntermediateDirectories: true)

        let socketPath = socketDir.appendingPathComponent("test.sock").path

        Self._currentPath.withLock { $0 = socketPath }
        defer {
            Self._currentPath.withLock { $0 = nil }
            try? FileManager.default.removeItem(at: socketDir)
        }

        try await function()
    }

    // MARK: Private

    private static let _currentPath = Mutex<String?>(nil)
}

// MARK: - MockSocketError

enum MockSocketError: Error, CustomStringConvertible {
    case notInScope

    // MARK: Internal

    var description: String {
        "MockSocketTrait.path accessed outside of a test annotated with .mockSocket"
    }
}

extension SuiteTrait where Self == MockSocketTrait {
    /// Provides a temporary Unix domain socket path for the duration of the test.
    static var mockSocket: Self {
        MockSocketTrait()
    }
}
