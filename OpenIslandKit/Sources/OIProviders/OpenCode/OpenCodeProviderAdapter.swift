import Foundation
package import OICore
import Synchronization

// MARK: - OpenCodeProviderAdapter

/// Top-level adapter that composes all OpenCode components and conforms to ``ProviderAdapter``.
///
/// Owns the ``OpenCodeSSEClient`` (event streaming), ``OpenCodeRESTClient`` (HTTP API),
/// ``OpenCodeServerDiscovery`` (server location), and ``OpenCodeEventNormalizer`` (event mapping).
/// Connects to OpenCode's HTTP server via SSE and normalizes events into a single
/// ``AsyncStream<ProviderEvent>``.
package final class OpenCodeProviderAdapter: ProviderAdapter, Sendable {
    // MARK: Lifecycle

    package init(configuredPort: Int? = nil) {
        self.discovery = OpenCodeServerDiscovery(configuredPort: configuredPort)
        self.state = Mutex(.init())
    }

    // MARK: Package

    package let providerID: ProviderID = .openCode
    package let metadata: ProviderMetadata = .metadata(for: .openCode)
    package let transportType: ProviderTransportType = .httpSSE

    package func start() async throws(ProviderStartupError) {
        let alreadyRunning = self.state.withLock { $0.isRunning }
        guard !alreadyRunning else {
            throw .alreadyRunning
        }

        // 1. Discover the OpenCode server
        let server = await discovery.discover()

        // 2. Check reachability
        let reachable = await discovery.checkReachability(server: server)
        guard reachable else {
            throw .httpServerUnreachable(host: server.host, port: server.port)
        }

        // 3. Create clients
        let restClient = OpenCodeRESTClient(baseURL: server.baseURL)
        let sseClient = OpenCodeSSEClient(baseURL: server.baseURL)

        // 4. Connect SSE (global endpoint for cross-project events)
        let sseStream = await sseClient.connect(endpoint: .global)

        // 5. Create the provider event stream
        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
            // Event stream — preserve ordering, don't drop events.
            bufferingPolicy: .bufferingOldest(128),
        )

        // 6. Start SSE processing task (detached to avoid inheriting caller isolation
        //    — prevents deadlock when stop() is called from the same context).
        //
        // The adapter tracks real session IDs and permission→session mappings
        // from SSE events. This is necessary because:
        // - SSE events carry the real OpenCode session ID (e.g. from `session.created`)
        // - Permission responses must use the real session ID in the REST URL
        // - `isSessionAlive` must match against real session IDs
        let adapter = self
        let sseTask = Task.detached {
            for await sseEvent in sseStream {
                guard !Task.isCancelled else { break }
                let events = OpenCodeEventNormalizer.normalize(sseEvent)
                for event in events {
                    // Track session IDs and permission mappings from SSE events
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

    package func stop() async {
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

        // Cancel SSE task, disconnect SSE client (which terminates the SSE
        // stream the task is iterating), then await the task so it is fully
        // stopped before we yield .sessionEnded events.
        extracted.sseTask?.cancel()
        if let sseClient = extracted.sseClient {
            await sseClient.disconnect()
        }
        await extracted.sseTask?.value

        // Emit session ended for all tracked sessions before finishing
        for sessionID in extracted.activeSessionIDs {
            extracted.continuation?.yield(.sessionEnded(sessionID))
        }

        // Finish the provider event stream
        extracted.continuation?.finish()
    }

    package func events() -> AsyncStream<ProviderEvent> {
        if let stream = state.withLock({ $0.eventStream }) {
            return stream
        }
        // Return an immediately-finished empty stream if not started.
        // No buffering policy needed — finished before any yield.
        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream()
        continuation.finish()
        return stream
    }

    package func respondToPermission(
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

    package func isSessionAlive(_ sessionID: String) -> Bool {
        self.state.withLock { adapterState in
            adapterState.isRunning && adapterState.activeSessionIDs.contains(sessionID)
        }
    }

    // MARK: Private

    private let discovery: OpenCodeServerDiscovery
    private let state: Mutex<AdapterState>

    /// Resets adapter state when the SSE stream ends naturally (server disconnected).
    ///
    /// Called only on non-cancelled termination — `stop()` handles its own cleanup.
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

/// Mutable state for the adapter, protected by `Mutex`.
private struct AdapterState: Sendable {
    var isRunning = false
    /// Real OpenCode session IDs observed from SSE events.
    var activeSessionIDs: Set<String> = []
    /// Maps permission request IDs to their originating OpenCode session IDs,
    /// so `respondToPermission` can target the correct REST endpoint.
    var permissionSessionMap: [String: String] = [:]
    var restClient: OpenCodeRESTClient?
    var sseClient: OpenCodeSSEClient?
    var eventStream: AsyncStream<ProviderEvent>?
    var eventContinuation: AsyncStream<ProviderEvent>.Continuation?
    var sseTask: Task<Void, Never>?
}

// MARK: - OpenCodePermissionResponseError

/// Errors from responding to an OpenCode permission request.
package enum OpenCodePermissionResponseError: Error, Sendable {
    /// The adapter is not connected to an OpenCode server.
    case notConnected
}
