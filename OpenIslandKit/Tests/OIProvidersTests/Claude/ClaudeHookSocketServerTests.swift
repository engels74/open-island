import Darwin
import Foundation
@testable import OIProviders
import Testing

// MARK: - SocketFDTests

struct SocketFDTests {
    @Test
    func `wraps file descriptor value`() {
        let fd = SocketFD(42)
        let value = fd.rawValue
        #expect(value == 42)
        fd.close()
    }

    @Test
    func `close consumes ownership`() {
        let fd = SocketFD(Darwin.socket(AF_UNIX, SOCK_STREAM, 0))
        let value = fd.rawValue
        #expect(value >= 0)
        fd.close()
        // After close, fd is consumed — cannot be used again (compile-time guarantee)
    }

    @Test
    func `deinit closes fd when not explicitly closed`() {
        let rawFD: Int32
        do {
            let fd = SocketFD(Darwin.socket(AF_UNIX, SOCK_STREAM, 0))
            rawFD = fd.rawValue
            #expect(rawFD >= 0)
            // fd goes out of scope here, deinit closes it
        }
        // Verify the fd is closed by trying to use it
        var statBuf = Darwin.stat()
        let result = fstat(rawFD, &statBuf)
        #expect(result == -1, "fd should be closed after deinit")
    }
}

// MARK: - PermissionConnectionTests

struct PermissionConnectionTests {
    // MARK: Internal

    @Test
    func `tracks request ID`() {
        let pair = self.makeSocketPair()
        let conn = PermissionConnection(
            clientFD: SocketFD(pair.write),
            requestID: "perm-123",
        )
        let id = conn.requestID
        #expect(id == "perm-123")
        Darwin.close(pair.read)
        // conn goes out of scope, SocketFD deinit closes write end
    }

    @Test
    func `is not expired when freshly created`() {
        let pair = self.makeSocketPair()
        let conn = PermissionConnection(
            clientFD: SocketFD(pair.write),
            requestID: "perm-456",
        )
        let expired = conn.isExpired
        #expect(!expired)
        Darwin.close(pair.read)
    }

    @Test
    func `respond writes data and closes connection`() {
        let pair = self.makeSocketPair()

        let conn = PermissionConnection(
            clientFD: SocketFD(pair.write),
            requestID: "perm-789",
        )

        let responseJSON = Data(#"{"decision":"allow"}"#.utf8)
        conn.respond(responseJSON)

        // Read from the other end of the pair
        var buffer = [UInt8](repeating: 0, count: 256)
        let bytesRead = Darwin.read(pair.read, &buffer, buffer.count)
        #expect(bytesRead > 0)

        let received = String(bytes: buffer[0 ..< bytesRead], encoding: .utf8)
        #expect(received == #"{"decision":"allow"}"#)

        Darwin.close(pair.read)
    }

    // MARK: Private

    /// Creates a connected socket pair for testing.
    private func makeSocketPair() -> (read: Int32, write: Int32) {
        var fds: [Int32] = [0, 0]
        let result = socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        precondition(result == 0, "socketpair failed: \(errno)")
        return (read: fds[0], write: fds[1])
    }
}

// MARK: - ClaudeHookSocketServerTests

@Suite(.tags(.socket), .serialized)
struct ClaudeHookSocketServerTests {
    // MARK: Internal

    @Test
    func `initializes with default socket path`() {
        let server = ClaudeHookSocketServer()
        #expect(server.socketPath == "/tmp/open-island-claude.sock")
    }

    @Test
    func `initializes with custom socket path`() {
        let server = ClaudeHookSocketServer(socketPath: "/tmp/test-hook.sock")
        #expect(server.socketPath == "/tmp/test-hook.sock")
    }

    @Test
    func `is not running before start`() {
        let server = ClaudeHookSocketServer(socketPath: uniqueSocketPath())
        #expect(!server.isRunning)
    }

    @Test(.timeLimit(.minutes(1)))
    func `starts and creates socket file`() throws {
        let path = self.uniqueSocketPath()
        let server = ClaudeHookSocketServer(socketPath: path)
        defer {
            server.stop()
            unlink(path)
        }

        // Must hold the stream reference — dropping it triggers onTermination → stop()
        let stream = try server.start()

        #expect(server.isRunning)
        #expect(FileManager.default.fileExists(atPath: path))

        withExtendedLifetime(stream) {}
    }

    @Test(.timeLimit(.minutes(1)))
    func `stop removes socket file`() throws {
        let path = self.uniqueSocketPath()
        let server = ClaudeHookSocketServer(socketPath: path)

        // Must hold the stream reference — dropping it triggers onTermination → stop()
        let stream = try server.start()
        #expect(server.isRunning)

        server.stop()
        #expect(!server.isRunning)
        #expect(!FileManager.default.fileExists(atPath: path))

        withExtendedLifetime(stream) {}
    }

    @Test(.timeLimit(.minutes(1)))
    func `accepts connection and receives data`() async throws {
        let path = self.uniqueSocketPath()
        let server = ClaudeHookSocketServer(socketPath: path)
        defer {
            server.stop()
            unlink(path)
        }

        let stream = try server.start()

        // Connect as a client and send data
        let testPayload = #"{"event":"test","session_id":"s1"}"# + "\n"
        self.sendToSocket(path: path, data: Data(testPayload.utf8))

        // Read from the async stream
        var received: Data?
        for await data in stream {
            received = data
            break
        }

        let receivedString = received.flatMap { String(data: $0, encoding: .utf8) }
        #expect(receivedString?.contains("test") == true)
    }

    @Test(.timeLimit(.minutes(1)))
    func `handles permission response round-trip`() throws {
        let path = self.uniqueSocketPath()
        let server = ClaudeHookSocketServer(socketPath: path)
        defer {
            server.stop()
            unlink(path)
        }

        // Must hold the stream reference — dropping it triggers onTermination → stop()
        let stream = try server.start()
        defer { withExtendedLifetime(stream) {} }

        // Create a socket pair to simulate a held-open permission connection
        var fds: [Int32] = [0, 0]
        let pairResult = socketpair(AF_UNIX, SOCK_STREAM, 0, &fds)
        #expect(pairResult == 0)

        let conn = PermissionConnection(
            clientFD: SocketFD(fds[1]),
            requestID: "req-abc",
        )
        server.registerPermissionConnection(conn)

        // Respond to the permission
        let response = Data(#"{"decision":{"behavior":"allow"}}"#.utf8)
        let sent = server.respondToPermission(requestID: "req-abc", data: response)
        #expect(sent)

        // Read the response from the other end
        var buffer = [UInt8](repeating: 0, count: 512)
        let bytesRead = Darwin.read(fds[0], &buffer, buffer.count)
        #expect(bytesRead > 0)

        let receivedJSON = String(bytes: buffer[0 ..< bytesRead], encoding: .utf8)
        #expect(receivedJSON == #"{"decision":{"behavior":"allow"}}"#)

        Darwin.close(fds[0])
    }

    @Test
    func `respondToPermission returns false for unknown ID`() {
        let server = ClaudeHookSocketServer(socketPath: uniqueSocketPath())
        let result = server.respondToPermission(requestID: "nonexistent", data: Data())
        #expect(!result)
    }

    @Test(.timeLimit(.minutes(1)))
    func `double start throws alreadyRunning`() throws {
        let path = self.uniqueSocketPath()
        let server = ClaudeHookSocketServer(socketPath: path)
        defer {
            server.stop()
            unlink(path)
        }

        // Must hold the stream reference — dropping it triggers onTermination → stop()
        let stream = try server.start()

        #expect(throws: SocketServerError.self) {
            _ = try server.start()
        }

        withExtendedLifetime(stream) {}
    }

    // MARK: Private

    // MARK: - Helpers

    /// Generate a unique socket path to avoid test interference.
    private func uniqueSocketPath() -> String {
        "/tmp/oi-test-\(UUID().uuidString.prefix(8)).sock"
    }

    /// Connect to a Unix domain socket and send data.
    private func sendToSocket(path: String, data: Data) {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    guard let srcBase = src.baseAddress else { return }
                    _ = memcpy(dest, srcBase, src.count)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            Darwin.close(fd)
            return
        }

        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            _ = Darwin.write(fd, base, buffer.count)
        }

        Darwin.close(fd)
    }
}
