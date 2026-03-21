import Darwin

// @preconcurrency: DispatchSource, DispatchQueue predate Sendable annotations
@preconcurrency import Dispatch
package import Foundation
import Synchronization

// MARK: - HookSocketBridge

/// Shared Unix domain socket server composed by Claude and Gemini hook providers.
///
/// Handles socket lifecycle, async event streaming, and permission connection
/// hold-open. Provider-specific logic is injected via ``HookSocketBridgeDelegate``.
package final class HookSocketBridge: Sendable {
    // MARK: Lifecycle

    package init(socketPath: String, queueLabel: String) {
        self.socketPath = socketPath
        self.queueLabel = queueLabel
        self.state = Mutex(.init())
    }

    // MARK: Package

    package let socketPath: String

    package var isRunning: Bool {
        self.state.withLock { $0.isRunning }
    }

    package func start(delegate: any HookSocketBridgeDelegate) throws(SocketServerError) -> AsyncStream<Data> {
        let alreadyRunning = self.state.withLock { $0.isRunning }
        guard !alreadyRunning else {
            throw .alreadyRunning
        }

        unlink(self.socketPath)

        let fd = try createAndBindSocket()

        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let (stream, continuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: .bufferingOldest(128),
        )

        let queue = DispatchQueue(label: self.queueLabel, qos: .userInitiated)

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

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak bridgeSelf] in
            bridgeSelf?.state.withLock { $0.permissions.removeExpired() }
        }
        timer.resume()

        self.state.withLock { state in
            state.isRunning = true
            state.serverFD = fd
            state.acceptSource = acceptSource
            state.expiryTimer = timer
            state.rawStreamContinuation = continuation
        }

        continuation.onTermination = { [weak bridgeSelf] _ in
            bridgeSelf?.stop()
        }

        return stream
    }

    package func stop() {
        // Extract before finishing — finish() triggers onTermination synchronously,
        // which would cause re-entrant Mutex access.
        let continuation = self.state.withLock { state -> AsyncStream<Data>.Continuation? in
            guard state.isRunning else { return nil }

            state.acceptSource?.cancel()
            state.acceptSource = nil

            state.expiryTimer?.cancel()
            state.expiryTimer = nil

            unlink(self.socketPath)

            let cont = state.rawStreamContinuation
            state.rawStreamContinuation = nil
            state.isRunning = false
            state.serverFD = nil
            state.permissions = PermissionsState()

            return cont
        }

        continuation?.finish()
    }

    @discardableResult
    package func respondToPermission(requestID: String, data: Data) -> Bool {
        guard let connection = state.withLock({ $0.permissions.remove(forID: requestID) }) else {
            return false
        }
        connection.respond(data)
        return true
    }

    package func registerPermissionConnection(_ connection: consuming PermissionConnection) {
        let id = connection.requestID
        let box = PermissionConnectionBox(connection: connection)
        self.state.withLock { $0.permissions.pending[id] = box }
    }

    // MARK: Private

    private let queueLabel: String
    private let state: Mutex<BridgeServerState>

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
                // Event was dropped — close immediately so the hook script
                // isn't left blocking on a response that will never arrive.
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

/// Provider-specific logic for identifying which events need held-open connections.
package protocol HookSocketBridgeDelegate: Sendable { // swiftlint:disable:this class_delegate_protocol
    func isPermissionRequest(_ data: Data) -> Bool
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
