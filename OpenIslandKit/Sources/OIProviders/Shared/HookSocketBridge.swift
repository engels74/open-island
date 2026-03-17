import Darwin

// @preconcurrency: DispatchSource, DispatchQueue predate Sendable annotations
@preconcurrency import Dispatch
package import Foundation
import Synchronization

// MARK: - HookSocketBridge

/// Shared GCD-based Unix domain socket server for hook-based providers.
///
/// Extracted from `ClaudeHookSocketServer` to provide a common socket infrastructure
/// that both Claude Code and Gemini CLI providers compose. The bridge handles:
/// - Socket lifecycle (create, bind, listen, accept, stop)
/// - Async event streaming via `AsyncStream<Data>`
/// - Permission connection hold-open with timeout and expiry
///
/// Provider-specific servers (e.g., `ClaudeHookSocketServer`, `GeminiHookSocketServer`)
/// compose this bridge and add their own event-name detection and permission-request
/// identification logic via the ``HookSocketBridgeDelegate`` protocol.
package final class HookSocketBridge: Sendable {
    // MARK: Lifecycle

    package init(socketPath: String, queueLabel: String) {
        self.socketPath = socketPath
        self.queueLabel = queueLabel
        self.state = Mutex(.init())
    }

    // MARK: Package

    /// The Unix domain socket path this bridge listens on.
    package let socketPath: String

    /// Whether the server is currently running.
    package var isRunning: Bool {
        self.state.withLock { $0.isRunning }
    }

    /// Start listening for connections.
    ///
    /// - Parameter delegate: Provides provider-specific logic for identifying permission
    ///   requests and extracting request IDs from raw event data.
    /// - Returns: An `AsyncStream<Data>` of raw JSON payloads received from hook scripts.
    package func start(delegate: any HookSocketBridgeDelegate) throws(SocketServerError) -> AsyncStream<Data> {
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

        // Create async stream with bounded buffer.
        // Event stream — preserve ordering, don't drop hook events.
        let (stream, continuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: .bufferingOldest(128),
        )

        let queue = DispatchQueue(label: self.queueLabel, qos: .userInitiated)

        // Accept source
        let acceptSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let bridgeSelf = self
        let delegateRef = delegate
        acceptSource.setEventHandler { [weak bridgeSelf] in
            bridgeSelf?.handleAccept(
                serverFD: fd,
                continuation: continuation,
                queue: queue,
                delegate: delegateRef,
            )
        }
        acceptSource.setCancelHandler {
            Darwin.close(fd)
        }
        acceptSource.resume()

        // Expiry timer — clean up expired permission connections every 60 seconds
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak bridgeSelf] in
            bridgeSelf?.state.withLock { $0.permissions.removeExpired() }
        }
        timer.resume()

        // Update state atomically
        self.state.withLock { state in
            state.isRunning = true
            state.serverFD = fd
            state.acceptSource = acceptSource
            state.expiryTimer = timer
            state.rawStreamContinuation = continuation
        }

        // Set onTermination for cleanup on consumer disconnect
        continuation.onTermination = { [weak bridgeSelf] _ in
            bridgeSelf?.stop()
        }

        return stream
    }

    /// Stop the server and clean up resources.
    package func stop() {
        // Extract continuation before the lock to avoid re-entrant access
        // (finish() triggers onTermination synchronously).
        let continuation = self.state.withLock { state -> AsyncStream<Data>.Continuation? in
            guard state.isRunning else { return nil }

            state.acceptSource?.cancel()
            state.acceptSource = nil

            state.expiryTimer?.cancel()
            state.expiryTimer = nil

            // Remove socket file
            unlink(self.socketPath)

            let cont = state.rawStreamContinuation
            state.rawStreamContinuation = nil
            state.isRunning = false
            state.serverFD = nil
            state.permissions = PermissionsState()

            return cont
        }

        // Finish the raw data stream so consumers (e.g., the detached
        // processing task in provider adapters) terminate cleanly.
        continuation?.finish()
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

    private let queueLabel: String
    private let state: Mutex<BridgeServerState>

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
        // Span<T> not applicable — Darwin socket APIs require raw pointer access
        // for sockaddr_un population and bind() calls.
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
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
        delegate: any HookSocketBridgeDelegate,
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
                // Event was lost — no consumer will ever see it. Close the
                // connection immediately so the hook script isn't left
                // blocking on a response that will never arrive.
                Darwin.close(clientFD)
                continue
            }

            // Hold the connection open for permission/blocking events so the
            // hook script can receive the approve/deny response.
            if delegate.isPermissionRequest(data) {
                let socketFD = SocketFD(clientFD)
                let requestID = delegate.extractRequestID(from: data) ?? UUID().uuidString
                let connection = PermissionConnection(clientFD: socketFD, requestID: requestID)
                self.registerPermissionConnection(connection)
            } else {
                Darwin.close(clientFD)
            }
        }
    }

    /// Read all available data from a client socket.
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
                accumulated.append(buffer.assumingMemoryBound(to: UInt8.self), count: bytesRead)
            } else {
                break
            }

            // Check if we've received a complete JSON message (newline-delimited)
            if accumulated.last == UInt8(ascii: "\n") {
                break
            }
        }

        return accumulated
    }

    private func logBufferWarning() {
        NSLog("[HookSocketBridge] WARNING: Event buffer full — consumer too slow. Events may be dropped.")
    }
}

// MARK: - HookSocketBridgeDelegate

/// Provider-specific logic for identifying permission requests in raw event data.
///
/// Each hook-based provider implements this to tell the bridge which events require
/// held-open connections (for permission responses) and how to extract request IDs.
package protocol HookSocketBridgeDelegate: Sendable { // swiftlint:disable:this class_delegate_protocol
    /// Check whether raw JSON data represents a permission/blocking event
    /// that requires holding the connection open for a response.
    func isPermissionRequest(_ data: Data) -> Bool

    /// Extract a unique request ID from raw JSON data for permission events.
    /// Returns `nil` if the ID cannot be extracted (a UUID fallback is used).
    func extractRequestID(from data: Data) -> String?
}

// MARK: - BridgeServerState

private struct BridgeServerState: Sendable {
    var isRunning = false
    var serverFD: Int32?
    var acceptSource: (any DispatchSourceRead)?
    var expiryTimer: (any DispatchSourceTimer)?
    var rawStreamContinuation: AsyncStream<Data>.Continuation?
    var permissions = PermissionsState()
}
