import Foundation
import Synchronization
import Testing

// MARK: - MockHTTPServerTrait

/// A test trait that starts a lightweight local HTTP server on a random port
/// before the test and stops it after the test completes.
///
/// Usage: Apply `.mockHTTPServer` to a `@Suite` or `@Test`. Access the
/// server's port via `MockHTTPServerTrait.port` or its base URL via
/// `MockHTTPServerTrait.baseURL` inside the test body.
struct MockHTTPServerTrait: SuiteTrait, TestScoping {
    // MARK: Internal

    /// The port the mock HTTP server is listening on in the current test scope.
    static var port: UInt16 {
        get throws {
            guard let value = _currentPort.withLock({ $0 }) else {
                throw MockHTTPServerError.notInScope
            }
            return value
        }
    }

    /// The base URL of the mock HTTP server (e.g. `http://127.0.0.1:12345`).
    static var baseURL: URL {
        get throws {
            let serverPort = try port
            guard let url = URL(string: "http://127.0.0.1:\(serverPort)") else {
                throw MockHTTPServerError.bindFailed
            }
            return url
        }
    }

    func provideScope(
        for test: Test,
        testCase: Test.Case?,
        performing function: @Sendable () async throws -> Void,
    ) async throws {
        let server = try MockHTTPServer()
        try server.start()
        let port = server.port

        Self._currentPort.withLock { $0 = port }
        defer {
            Self._currentPort.withLock { $0 = nil }
            server.stop()
        }

        try await function()
    }

    // MARK: Private

    private static let _currentPort = Mutex<UInt16?>(nil)
}

// MARK: - MockHTTPServerError

enum MockHTTPServerError: Error, CustomStringConvertible {
    case notInScope
    case bindFailed

    // MARK: Internal

    var description: String {
        switch self {
        case .notInScope:
            "MockHTTPServerTrait.port accessed outside of a test annotated with .mockHTTPServer"
        case .bindFailed:
            "Failed to bind mock HTTP server to a random port"
        }
    }
}

extension SuiteTrait where Self == MockHTTPServerTrait {
    /// Starts a mock HTTP server on a random port for the duration of the test.
    static var mockHTTPServer: Self {
        MockHTTPServerTrait()
    }
}

// MARK: - MockHTTPServer

/// A minimal HTTP server that listens on a random port and responds with
/// a fixed 200 OK to every request. Uses POSIX sockets — no third-party deps.
final class MockHTTPServer: Sendable {
    // MARK: Lifecycle

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MockHTTPServerError.bindFailed }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // random port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw MockHTTPServerError.bindFailed
        }

        var boundAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(fd, sockPtr, &addrLen)
            }
        }

        self.port = UInt16(bigEndian: boundAddr.sin_port)
        self.serverFD = fd
    }

    // MARK: Internal

    let port: UInt16

    func start() throws {
        guard listen(self.serverFD, 5) == 0 else {
            close(self.serverFD)
            throw MockHTTPServerError.bindFailed
        }

        let server = self

        Task.detached {
            while server._running.load(ordering: .acquiring) {
                var clientAddr = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                        accept(server.serverFD, sockPtr, &clientLen)
                    }
                }

                if clientFD < 0 { break }

                var buffer = [UInt8](repeating: 0, count: 1024)
                _ = recv(clientFD, &buffer, buffer.count, 0)

                let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"
                _ = response.withCString { ptr in
                    send(clientFD, ptr, strlen(ptr), 0)
                }
                close(clientFD)
            }
        }
    }

    func stop() {
        self._running.store(false, ordering: .releasing)
        close(self.serverFD)
    }

    // MARK: Private

    private let serverFD: Int32
    private let _running = Atomic<Bool>(true)
}
