import Foundation
public import OICore
import Synchronization

// MARK: - AdapterState

private struct AdapterState: Sendable {
    var isRunning = false
    var eventStream: AsyncStream<ProviderEvent>?
    var eventContinuation: AsyncStream<ProviderEvent>.Continuation?
    var processingTask: Task<Void, Never>?
    var lastAfterModelTime: Date?
}

// MARK: - GeminiCLIProviderAdapter

/// Top-level adapter composing all Gemini CLI components, conforming to ``ProviderAdapter``.
///
/// Uses the same hook-socket transport as Claude Code: hook scripts send JSON events
/// over a Unix domain socket, with `BeforeTool` connections held open for permissions.
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

        try? await GeminiHookInstaller.install()

        let rawStream: AsyncStream<Data>
        do {
            rawStream = try self.socketServer.start()
        } catch {
            throw self.mapSocketError(error)
        }

        // Detached so it doesn't inherit the caller's isolation domain —
        // prevents deadlock when stop() is called from the same context.
        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(128),
        )

        let adapter = self
        let processingTask = Task.detached { [weak adapter] in
            for await rawData in rawStream {
                guard !Task.isCancelled else { break }
                adapter?.processRawEvent(rawData, continuation: continuation)
            }
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
        // Extract before finishing — finish() triggers onTermination synchronously,
        // which would cause re-entrant Mutex access.
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

        processingTask?.cancel()
        self.socketServer.stop()
        continuation?.finish()
    }

    public func events() -> AsyncStream<ProviderEvent> {
        if let stream = self.state.withLock({ $0.eventStream }) {
            return stream
        }
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

    private func processRawEvent(_ data: Data, continuation: AsyncStream<ProviderEvent>.Continuation) {
        let lastTime = self.state.withLock { $0.lastAfterModelTime }

        do {
            let (events, updatedTime) = try GeminiEventNormalizer.normalize(
                data,
                lastAfterModelTime: lastTime,
            )

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
