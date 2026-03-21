import Foundation
public import OICore
import Synchronization

// MARK: - AdapterState

private struct AdapterState: Sendable {
    var isRunning = false
    var eventStream: AsyncStream<ProviderEvent>?
    var eventContinuation: AsyncStream<ProviderEvent>.Continuation?
    var processingTask: Task<Void, Never>?
}

// MARK: - ClaudeProviderAdapter

/// Top-level adapter that composes all Claude Code components and conforms to ``ProviderAdapter``.
///
/// Owns the socket server, event normalizer pipeline, and (when available) hook installer
/// and conversation parser. Merges socket events into a single ``AsyncStream<ProviderEvent>``.
public final class ClaudeProviderAdapter: ProviderAdapter, Sendable {
    // MARK: Lifecycle

    public init(socketPath: String = "/tmp/open-island-claude.sock") {
        self.socketServer = ClaudeHookSocketServer(socketPath: socketPath)
        self.state = Mutex(.init())
    }

    // MARK: Public

    public let providerID: ProviderID = .claude
    public let metadata: ProviderMetadata = .metadata(for: .claude)
    public let transportType: ProviderTransportType = .hookSocket

    public func start() async throws(ProviderStartupError) {
        let alreadyRunning = self.state.withLock { $0.isRunning }
        guard !alreadyRunning else {
            throw .alreadyRunning
        }

        // TODO: Call ClaudeHookInstaller.install() once Task 3.4 lands
        // try? await ClaudeHookInstaller.install()

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

    private let socketServer: ClaudeHookSocketServer
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
        let hookEvent: ClaudeHookEvent
        do {
            hookEvent = try JSONDecoder().decode(ClaudeHookEvent.self, from: data)
        } catch {
            NSLog("[ClaudeProviderAdapter] Failed to decode hook event: \(error)")
            return
        }

        do {
            let providerEvents = try ClaudeEventNormalizer.normalize(hookEvent)
            for providerEvent in providerEvents {
                continuation.yield(providerEvent)
            }
        } catch {
            NSLog("[ClaudeProviderAdapter] Failed to normalize event '\(hookEvent.hookEventName)': \(error)")
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

// MARK: - PermissionResponseError

package enum PermissionResponseError: Error, Sendable {
    case noConnectionFound(requestID: String)
}
