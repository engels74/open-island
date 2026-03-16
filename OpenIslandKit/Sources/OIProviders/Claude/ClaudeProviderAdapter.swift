import Foundation
package import OICore
import Synchronization

// MARK: - AdapterState

/// Mutable state for the adapter, protected by `Mutex`.
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
package final class ClaudeProviderAdapter: ProviderAdapter, Sendable {
    // MARK: Lifecycle

    package init(socketPath: String = "/tmp/open-island-claude.sock") {
        self.socketServer = ClaudeHookSocketServer(socketPath: socketPath)
        self.state = Mutex(.init())
    }

    // MARK: Package

    package let providerID: ProviderID = .claude
    package let metadata: ProviderMetadata = .metadata(for: .claude)
    package let transportType: ProviderTransportType = .hookSocket

    package func start() async throws(ProviderStartupError) {
        let alreadyRunning = self.state.withLock { $0.isRunning }
        guard !alreadyRunning else {
            throw .alreadyRunning
        }

        // 1. Install hooks (best-effort — don't fail if already installed or installer unavailable)
        // TODO: Call ClaudeHookInstaller.install() once Task 3.4 lands
        // try? await ClaudeHookInstaller.install()

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

    package func stop() async {
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

    package func events() -> AsyncStream<ProviderEvent> {
        if let stream = self.state.withLock({ $0.eventStream }) {
            return stream
        }
        // Return an immediately-finished stream if not started
        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream()
        continuation.finish()
        return stream
    }

    package func respondToPermission(
        _ request: PermissionRequest,
        decision: PermissionDecision,
    ) async throws {
        let responseData = try Self.encodePermissionResponse(decision)
        let sent = self.socketServer.respondToPermission(requestID: request.id, data: responseData)
        if !sent {
            throw PermissionResponseError.noConnectionFound(requestID: request.id)
        }
    }

    package func isSessionAlive(_ sessionID: String) -> Bool {
        // TODO: Check kill(pid, 0) once session → PID tracking is implemented.
        // For now, return true — actual PID checking will be added when we have
        // session PID mapping from SessionStart events.
        true
    }

    // MARK: Private

    private let socketServer: ClaudeHookSocketServer
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

    /// Decode raw socket data into a ClaudeHookEvent, normalize it, and yield to the stream.
    private func processRawEvent(_ data: Data, continuation: AsyncStream<ProviderEvent>.Continuation) {
        // Decode raw JSON → ClaudeHookEvent
        let hookEvent: ClaudeHookEvent
        do {
            hookEvent = try JSONDecoder().decode(ClaudeHookEvent.self, from: data)
        } catch {
            // Malformed JSON — log and skip
            NSLog("[ClaudeProviderAdapter] Failed to decode hook event: \(error)")
            return
        }

        // Normalize → ProviderEvent
        do {
            if let providerEvent = try ClaudeEventNormalizer.normalize(hookEvent) {
                continuation.yield(providerEvent)
            }
            // nil means the event has no ProviderEvent equivalent (e.g., Setup) — skip
        } catch {
            NSLog("[ClaudeProviderAdapter] Failed to normalize event '\(hookEvent.hookEventName)': \(error)")
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

// MARK: - PermissionResponseError

/// Errors from responding to a permission request.
package enum PermissionResponseError: Error, Sendable {
    /// No held-open connection found for the given request ID.
    case noConnectionFound(requestID: String)
}
