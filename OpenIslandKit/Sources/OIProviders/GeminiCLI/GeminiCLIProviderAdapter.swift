import Foundation
public import OICore
import Synchronization

// MARK: - AdapterState

/// Mutable state for the adapter, protected by `Mutex`.
private struct AdapterState: Sendable {
    var isRunning = false
    var eventStream: AsyncStream<ProviderEvent>?
    var eventContinuation: AsyncStream<ProviderEvent>.Continuation?
    var processingTask: Task<Void, Never>?
    var lastAfterModelTime: Date?
}

// MARK: - GeminiCLIProviderAdapter

/// Top-level adapter that composes all Gemini CLI components and conforms to ``ProviderAdapter``.
///
/// Owns the socket server, event normalizer pipeline, and hook installer.
/// Merges socket events into a single ``AsyncStream<ProviderEvent>``.
///
/// Gemini CLI uses a hook-based transport identical to Claude Code's architecture:
/// hook scripts send JSON events over a Unix domain socket, with `BeforeTool`
/// connections held open for permission interception.
public final class GeminiCLIProviderAdapter: ProviderAdapter, Sendable {
    // MARK: Lifecycle

    public init(socketPath: String = "/tmp/open-island-gemini.sock") {
        self.socketServer = GeminiHookSocketServer(socketPath: socketPath)
        self.state = Mutex(.init())
    }

    // MARK: Public

    public let providerID: ProviderID = .geminiCLI
    public let metadata: ProviderMetadata = .metadata(for: .geminiCLI)
    public let transportType: ProviderTransportType = .hookSocket

    public func start() async throws(ProviderStartupError) {
        let alreadyRunning = self.state.withLock { $0.isRunning }
        guard !alreadyRunning else {
            throw .alreadyRunning
        }

        // 1. Install hooks (best-effort — don't fail if already installed)
        try? await GeminiHookInstaller.install()

        // 2. Start socket server
        let rawStream: AsyncStream<Data>
        do {
            rawStream = try self.socketServer.start()
        } catch {
            throw self.mapSocketError(error)
        }

        // 3. Create the merged event stream.
        //    The event processing task runs detached so it doesn't inherit
        //    the caller's isolation domain — prevents deadlock when stop()
        //    is called from the same context.
        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
            // Event stream — preserve ordering, don't drop events.
            bufferingPolicy: .bufferingOldest(128),
        )

        let adapter = self
        let processingTask = Task.detached { [weak adapter] in
            for await rawData in rawStream {
                guard !Task.isCancelled else { break }
                adapter?.processRawEvent(rawData, continuation: continuation)
            }
            // Raw stream ended — finish the provider event stream
            continuation.finish()
        }

        self.state.withLock { state in
            state.isRunning = true
            state.eventStream = stream
            state.eventContinuation = continuation
            state.processingTask = processingTask
        }
    }

    public func stop() async {
        // Extract continuation and task before finishing to avoid re-entrant
        // Mutex access (finish() triggers onTermination synchronously).
        let (continuation, processingTask) = self.state.withLock { state -> (AsyncStream<ProviderEvent>.Continuation?, Task<Void, Never>?) in
            guard state.isRunning else { return (nil, nil) }

            let cont = state.eventContinuation
            let task = state.processingTask
            state.eventContinuation = nil
            state.eventStream = nil
            state.processingTask = nil
            state.isRunning = false
            state.lastAfterModelTime = nil
            return (cont, task)
        }

        // Cancel the detached processing task.
        processingTask?.cancel()

        // Stop the socket server — this finishes the raw data stream,
        // allowing the detached processing task to terminate cleanly.
        self.socketServer.stop()

        // Finish the provider event stream for consumers.
        continuation?.finish()
    }

    public func events() -> AsyncStream<ProviderEvent> {
        if let stream = self.state.withLock({ $0.eventStream }) {
            return stream
        }
        // Return an immediately-finished empty stream if not started.
        // No buffering policy needed — finished before any yield.
        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream()
        continuation.finish()
        return stream
    }

    public func respondToPermission(
        _ request: PermissionRequest,
        decision: PermissionDecision,
    ) async throws {
        let responseData = try Self.encodePermissionResponse(decision)
        let sent = self.socketServer.respondToPermission(requestID: request.id, data: responseData)
        if !sent {
            throw PermissionResponseError.noConnectionFound(requestID: request.id)
        }
    }

    public func isSessionAlive(_ sessionID: String) -> Bool {
        // TODO: Check kill(pid, 0) once session → PID tracking is implemented.
        // For now, return true — actual PID checking will be added when we have
        // session PID mapping from SessionStart events.
        true
    }

    // MARK: Private

    private let socketServer: GeminiHookSocketServer
    private let state: Mutex<AdapterState>

    /// Encode a permission decision to JSON data for the socket response.
    private static func encodePermissionResponse(_ decision: PermissionDecision) throws -> Data {
        struct Response: Encodable {
            let decision: DecisionPayload
        }
        struct DecisionPayload: Encodable {
            let behavior: String
            let reason: String?
        }

        let payload = switch decision {
        case .allow:
            DecisionPayload(behavior: "allow", reason: nil)
        case let .deny(reason):
            DecisionPayload(behavior: "deny", reason: reason)
        }

        return try JSONEncoder().encode(Response(decision: payload))
    }

    /// Decode raw socket data, normalize via ``GeminiEventNormalizer``, and yield to the stream.
    private func processRawEvent(_ data: Data, continuation: AsyncStream<ProviderEvent>.Continuation) {
        let lastTime = self.state.withLock { $0.lastAfterModelTime }

        do {
            let (events, updatedTime) = try GeminiEventNormalizer.normalize(
                data,
                lastAfterModelTime: lastTime,
            )

            // Update the throttle time if it changed
            if updatedTime != lastTime {
                self.state.withLock { $0.lastAfterModelTime = updatedTime }
            }

            for event in events {
                continuation.yield(event)
            }
        } catch {
            NSLog("[GeminiCLIProviderAdapter] Failed to normalize event: \(error)")
        }
    }

    /// Map socket server errors to provider startup errors.
    private func mapSocketError(_ error: SocketServerError) -> ProviderStartupError {
        switch error {
        case .socketCreationFailed,
             .bindFailed,
             .listenFailed,
             .pathTooLong:
            .socketCreationFailed(path: self.socketServer.socketPath)
        case .alreadyRunning:
            .alreadyRunning
        }
    }
}
