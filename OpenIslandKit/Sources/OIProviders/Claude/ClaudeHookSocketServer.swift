import Darwin

// @preconcurrency: DispatchSource, DispatchQueue predate Sendable annotations
@preconcurrency import Dispatch
package import Foundation
import Synchronization

// MARK: - PermissionsState

/// Mutable state for tracking pending permission connections.
struct PermissionsState: Sendable {
    /// Pending permission connections keyed by request ID.
    /// Values are boxed to allow `~Copyable` PermissionConnection in a dictionary.
    var pending: [String: PermissionConnectionBox] = [:]

    mutating func insert(_ connection: consuming PermissionConnection, forID id: String) {
        self.pending[id] = PermissionConnectionBox(connection: connection)
    }

    mutating func remove(forID id: String) -> PermissionConnection? {
        self.pending.removeValue(forKey: id)?.take()
    }

    /// Remove all expired connections.
    mutating func removeExpired() {
        let expiredKeys = self.pending.keys.filter { self.pending[$0]?.isExpired == true }
        for key in expiredKeys {
            _ = self.pending.removeValue(forKey: key)
        }
    }
}

// MARK: - PermissionConnectionBox

/// Sendable box for `~Copyable` `PermissionConnection` to allow storage in a dictionary.
final class PermissionConnectionBox: Sendable {
    // MARK: Lifecycle

    init(connection: consuming PermissionConnection) {
        self._connection = Mutex(connection)
    }

    deinit {
        // If the connection was never taken, Mutex's value deinit
        // will run PermissionConnection's deinit, closing the fd.
    }

    // MARK: Internal

    var isExpired: Bool {
        self._connection.withLock { $0?.isExpired ?? true }
    }

    /// Take ownership of the connection, leaving nil behind.
    func take() -> PermissionConnection? {
        self._connection.withLock { connection in
            guard let conn = connection.take() else { return nil }
            return conn
        }
    }

    // MARK: Private

    private let _connection: Mutex<PermissionConnection?>
}

// MARK: - ClaudeHookSocketServer

/// GCD-based Unix domain socket server that receives events from Claude Code hook scripts.
///
/// The server listens on a configurable Unix domain socket path (default:
/// `/tmp/open-island-claude.sock`). Hook scripts connect and send JSON payloads.
/// For permission requests, the client connection is held open until the user
/// responds via `respondToPermission(_:data:)`.
///
/// Events are bridged from GCD callbacks to Swift concurrency via
/// `AsyncStream.makeStream()` with `.bufferingOldest(128)`.
package final class ClaudeHookSocketServer: Sendable {
    // MARK: Lifecycle

    package init(socketPath: String = "/tmp/open-island-claude.sock") {
        self.socketPath = socketPath
        self.state = Mutex(.init())
    }

    // MARK: Package

    /// The Unix domain socket path this server listens on.
    package let socketPath: String

    /// Whether the server is currently running.
    package var isRunning: Bool {
        self.state.withLock { $0.isRunning }
    }

    /// Start listening for connections.
    ///
    /// Returns an `AsyncStream<Data>` of raw JSON payloads received from hook scripts.
    /// The server emits raw `Data` — event parsing is handled downstream (Task 3.2).
    package func start() throws(SocketServerError) -> AsyncStream<Data> {
        let alreadyRunning = self.state.withLock { $0.isRunning }
        guard !alreadyRunning else {
            throw .alreadyRunning
        }

        // Remove stale socket file
        unlink(self.socketPath)

        let fd = try createAndBindSocket()

        // Set non-blocking
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        // Create async stream with bounded buffer
        let (stream, continuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: .bufferingOldest(128),
        )

        let queue = DispatchQueue(label: "open-island.claude-hook-socket", qos: .userInitiated)

        // Accept source
        let acceptSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let serverSelf = self
        acceptSource.setEventHandler { [weak serverSelf] in
            serverSelf?.handleAccept(serverFD: fd, continuation: continuation, queue: queue)
        }
        acceptSource.setCancelHandler {
            Darwin.close(fd)
        }
        acceptSource.resume()

        // Expiry timer — clean up expired permission connections every 60 seconds
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak serverSelf] in
            serverSelf?.state.withLock { $0.permissions.removeExpired() }
        }
        timer.resume()

        // Update state atomically
        self.state.withLock { state in
            state.isRunning = true
            state.serverFD = fd
            state.acceptSource = acceptSource
            state.expiryTimer = timer
        }

        // Set onTermination for cleanup on consumer disconnect
        continuation.onTermination = { [weak serverSelf] _ in
            serverSelf?.stop()
        }

        return stream
    }

    /// Stop the server and clean up resources.
    package func stop() {
        self.state.withLock { state in
            guard state.isRunning else { return }

            state.acceptSource?.cancel()
            state.acceptSource = nil

            state.expiryTimer?.cancel()
            state.expiryTimer = nil

            // Remove socket file
            unlink(self.socketPath)

            state.isRunning = false
            state.serverFD = nil
            state.permissions = PermissionsState()
        }
    }

    /// Respond to a pending permission request.
    ///
    /// Finds the held-open connection for the given request ID, writes the
    /// JSON response data, and closes the connection.
    ///
    /// - Parameters:
    ///   - requestID: The permission request ID to respond to.
    ///   - data: JSON response data to send back to the hook script.
    /// - Returns: `true` if the response was sent, `false` if no pending connection was found.
    @discardableResult
    package func respondToPermission(requestID: String, data: Data) -> Bool {
        guard let connection = state.withLock({ $0.permissions.remove(forID: requestID) }) else {
            return false
        }
        connection.respond(data)
        return true
    }

    /// Register a held-open permission connection.
    package func registerPermissionConnection(_ connection: consuming PermissionConnection) {
        let id = connection.requestID
        let box = PermissionConnectionBox(connection: connection)
        self.state.withLock { $0.permissions.pending[id] = box }
    }

    // MARK: Private

    private let state: Mutex<ServerState>

    /// Lightweight check for PermissionRequest events without full JSON decoding.
    private static func isPermissionRequest(_ data: Data) -> Bool {
        guard let str = String(data: data, encoding: .utf8) else { return false }
        return str.contains("\"hook_event_name\":\"PermissionRequest\"")
            || str.contains("\"hook_event_name\": \"PermissionRequest\"")
    }

    /// Extract the request ID from raw JSON data for PermissionRequest events.
    private static func extractRequestID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Try session_id first as a unique identifier, then fall back to tool_use_id
        return json["session_id"] as? String ?? json["tool_use_id"] as? String
    }

    /// Create a Unix domain socket, bind, and listen.
    private func createAndBindSocket() throws(SocketServerError) -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw .socketCreationFailed(errno: errno)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = self.socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            throw .pathTooLong(self.socketPath)
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            // Pointer valid only within this closure scope — never escape.
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    guard let srcBase = src.baseAddress else { return }
                    _ = memcpy(dest, srcBase, src.count)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw .bindFailed(errno: errno)
        }

        guard Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd)
            throw .listenFailed(errno: errno)
        }

        return fd
    }

    private func handleAccept(
        serverFD: Int32,
        continuation: AsyncStream<Data>.Continuation,
        queue: DispatchQueue,
    ) {
        // Accept may have multiple pending connections
        while true {
            let clientFD = Darwin.accept(serverFD, nil, nil)
            guard clientFD >= 0 else { break }

            let data = self.readClient(fd: clientFD)

            guard !data.isEmpty else {
                Darwin.close(clientFD)
                continue
            }

            let result = continuation.yield(data)
            if case .dropped = result {
                self.logBufferWarning()
            }

            // Hold the connection open for PermissionRequest events so the
            // Python hook script can receive the approve/deny response.
            if Self.isPermissionRequest(data) {
                let socketFD = SocketFD(clientFD)
                let requestID = Self.extractRequestID(from: data) ?? UUID().uuidString
                let connection = PermissionConnection(clientFD: socketFD, requestID: requestID)
                self.registerPermissionConnection(connection)
            } else {
                Darwin.close(clientFD)
            }
        }
    }

    /// Read all available data from a client socket.
    ///
    /// Returns the raw data without closing the fd — the caller decides
    /// whether to close or hold the connection open.
    private func readClient(fd: Int32) -> Data {
        var accumulated = Data()
        let bufferSize = 8192
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
        defer { buffer.deallocate() }

        // Set client socket to blocking for read
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)

        while true {
            let bytesRead = Darwin.read(fd, buffer, bufferSize)
            if bytesRead > 0 {
                // Pointer valid only within this scope — data is copied into Data.
                accumulated.append(buffer.assumingMemoryBound(to: UInt8.self), count: bytesRead)
            } else {
                // EOF or error
                break
            }

            // Check if we've received a complete JSON message (newline-delimited)
            if accumulated.last == UInt8(ascii: "\n") || bytesRead < bufferSize {
                break
            }
        }

        return accumulated
    }

    private func logBufferWarning() {
        // Using os_log would be ideal, but NSLog is simpler and available everywhere
        NSLog("[ClaudeHookSocketServer] WARNING: Event buffer full — consumer too slow. Events may be dropped.")
    }
}

// MARK: - ServerState

private struct ServerState: Sendable {
    var isRunning = false
    var serverFD: Int32?
    var acceptSource: (any DispatchSourceRead)?
    var expiryTimer: (any DispatchSourceTimer)?
    var permissions = PermissionsState()
}

// MARK: - SocketServerError

/// Errors that can occur when starting the socket server.
package enum SocketServerError: Error, Sendable {
    case socketCreationFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case listenFailed(errno: Int32)
    case pathTooLong(String)
    case alreadyRunning
}
