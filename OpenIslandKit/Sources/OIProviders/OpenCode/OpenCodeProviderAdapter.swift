import Foundation
public import OICore
import Synchronization

// MARK: - OpenCodeProviderAdapter

/// Connects to OpenCode's HTTP server via SSE and normalizes events into ``ProviderEvent``.
public final class OpenCodeProviderAdapter: ProviderAdapter, Sendable {
    // MARK: Lifecycle

    public init(configuredPort: Int? = nil) {
        self.discovery = OpenCodeServerDiscovery(configuredPort: configuredPort)
        self.state = Mutex(.init())
    }

    // MARK: Public

    public let providerID: ProviderID = .openCode
    public let metadata: ProviderMetadata = .metadata(for: .openCode)
    public let transportType: ProviderTransportType = .httpSSE

    public func start() async throws(ProviderStartupError) {
        let alreadyRunning = self.state.withLock { $0.isRunning }
        guard !alreadyRunning else {
            throw .alreadyRunning
        }

        let server = await discovery.discover()

        let reachable = await discovery.checkReachability(server: server)
        guard reachable else {
            throw .httpServerUnreachable(host: server.host, port: server.port)
        }

        let restClient = OpenCodeRESTClient(baseURL: server.baseURL)
        let sseClient = OpenCodeSSEClient(baseURL: server.baseURL)

        let sseStream = await sseClient.connect(endpoint: .global)

        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(128),
        )

        // Detached to avoid inheriting caller isolation — prevents deadlock
        // when stop() is called from the same context.
        //
        // Tracks real session IDs and permission→session mappings from SSE
        // events so respondToPermission can target the correct REST endpoint.
        let adapter = self
        let sseTask = Task.detached {
            for await sseEvent in sseStream {
                guard !Task.isCancelled else { break }
                let events = OpenCodeEventNormalizer.normalize(sseEvent)
                for event in events {
                    switch event {
                    case let .sessionStarted(sessionID, _, _):
                        adapter.state.withLock { _ = $0.activeSessionIDs.insert(sessionID) }
                    case let .sessionEnded(sessionID):
                        adapter.state.withLock { _ = $0.activeSessionIDs.remove(sessionID) }
                    case let .permissionRequested(sessionID, request):
                        adapter.state.withLock { $0.permissionSessionMap[request.id] = sessionID }
                    default:
                        break
                    }
                    continuation.yield(event)
                }
            }
            guard !Task.isCancelled else { return }
            adapter.handleNaturalSSETermination(continuation: continuation)
        }

        self.state.withLock { adapterState in
            adapterState.isRunning = true
            adapterState.restClient = restClient
            adapterState.sseClient = sseClient
            adapterState.eventStream = stream
            adapterState.eventContinuation = continuation
            adapterState.sseTask = sseTask
        }
    }

    public func stop() async {
        let extracted = self.state.withLock { adapterState -> (
            continuation: AsyncStream<ProviderEvent>.Continuation?,
            activeSessionIDs: Set<String>,
            sseClient: OpenCodeSSEClient?,
            sseTask: Task<Void, Never>?
        ) in
            guard adapterState.isRunning else {
                return (nil, [], nil, nil)
            }

            let cont = adapterState.eventContinuation
            let sessions = adapterState.activeSessionIDs
            let sse = adapterState.sseClient
            let task = adapterState.sseTask

            adapterState.eventContinuation = nil
            adapterState.eventStream = nil
            adapterState.isRunning = false
            adapterState.activeSessionIDs.removeAll()
            adapterState.permissionSessionMap.removeAll()
            adapterState.restClient = nil
            adapterState.sseClient = nil
            adapterState.sseTask = nil

            return (cont, sessions, sse, task)
        }

        // Disconnect SSE client (terminates the stream the task is iterating),
        // then await the task so it is fully stopped before yielding .sessionEnded.
        extracted.sseTask?.cancel()
        if let sseClient = extracted.sseClient {
            await sseClient.disconnect()
        }
        await extracted.sseTask?.value

        for sessionID in extracted.activeSessionIDs {
            extracted.continuation?.yield(.sessionEnded(sessionID))
        }

        extracted.continuation?.finish()
    }

    public func events() -> AsyncStream<ProviderEvent> {
        if let stream = state.withLock({ $0.eventStream }) {
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
        let (restClient, sessionID) = self.state.withLock { adapterState in
            let sid = adapterState.permissionSessionMap.removeValue(forKey: request.id)
            return (adapterState.restClient, sid)
        }

        guard let restClient, let sessionID else {
            throw OpenCodePermissionResponseError.notConnected
        }

        let allow = switch decision {
        case .allow: true
        case .deny: false
        }

        let reason: String? = switch decision {
        case .allow: nil
        case let .deny(reason): reason
        }

        let ocDecision = OpenCodePermissionDecision(allow: allow, reason: reason)
        _ = try await restClient.respondToPermission(
            sessionID: sessionID,
            permissionID: request.id,
            decision: ocDecision,
        )
    }

    public func isSessionAlive(_ sessionID: String) -> Bool {
        self.state.withLock { adapterState in
            adapterState.isRunning && adapterState.activeSessionIDs.contains(sessionID)
        }
    }

    // MARK: Private

    private let discovery: OpenCodeServerDiscovery
    private let state: Mutex<AdapterState>

    /// Called only on non-cancelled SSE termination — `stop()` handles its own cleanup.
    private func handleNaturalSSETermination(
        continuation: AsyncStream<ProviderEvent>.Continuation,
    ) {
        let sessionIDs = self.state.withLock { adapterState -> Set<String> in
            guard adapterState.isRunning else { return [] }
            let sessions = adapterState.activeSessionIDs
            adapterState.isRunning = false
            adapterState.activeSessionIDs.removeAll()
            adapterState.permissionSessionMap.removeAll()
            adapterState.restClient = nil
            adapterState.sseClient = nil
            adapterState.sseTask = nil
            adapterState.eventContinuation = nil
            adapterState.eventStream = nil
            return sessions
        }
        for sessionID in sessionIDs {
            continuation.yield(.sessionEnded(sessionID))
        }
        continuation.finish()
    }
}

// MARK: - AdapterState

private struct AdapterState: Sendable {
    var isRunning = false
    var activeSessionIDs: Set<String> = []
    /// Maps permission request IDs → session IDs for REST endpoint targeting.
    var permissionSessionMap: [String: String] = [:]
    var restClient: OpenCodeRESTClient?
    var sseClient: OpenCodeSSEClient?
    var eventStream: AsyncStream<ProviderEvent>?
    var eventContinuation: AsyncStream<ProviderEvent>.Continuation?
    var sseTask: Task<Void, Never>?
}

// MARK: - OpenCodePermissionResponseError

package enum OpenCodePermissionResponseError: Error, Sendable {
    case notConnected
}
