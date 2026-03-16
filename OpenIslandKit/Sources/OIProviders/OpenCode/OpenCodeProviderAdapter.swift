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
            bufferingPolicy: .bufferingOldest(128),
        )

        // 6. Start SSE processing task
        let sseTask = Task.detached {
            for await sseEvent in sseStream {
                guard !Task.isCancelled else { break }
                let events = OpenCodeEventNormalizer.normalize(sseEvent)
                for event in events {
                    continuation.yield(event)
                }
            }
            continuation.finish()
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
            sessionID: String?,
            sseClient: OpenCodeSSEClient?,
            sseTask: Task<Void, Never>?
        ) in
            guard adapterState.isRunning else {
                return (nil, nil, nil, nil)
            }

            let cont = adapterState.eventContinuation
            let sid = adapterState.sessionID
            let sse = adapterState.sseClient
            let task = adapterState.sseTask

            adapterState.eventContinuation = nil
            adapterState.eventStream = nil
            adapterState.isRunning = false
            adapterState.sessionID = nil
            adapterState.restClient = nil
            adapterState.sseClient = nil
            adapterState.sseTask = nil

            return (cont, sid, sse, task)
        }

        // Cancel SSE processing task
        extracted.sseTask?.cancel()

        // Disconnect SSE client
        if let sseClient = extracted.sseClient {
            await sseClient.disconnect()
        }

        // Emit session ended before finishing
        if let sid = extracted.sessionID {
            extracted.continuation?.yield(.sessionEnded(sid))
        }

        // Finish the provider event stream
        extracted.continuation?.finish()
    }

    package func events() -> AsyncStream<ProviderEvent> {
        if let stream = state.withLock({ $0.eventStream }) {
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
        let (restClient, sessionID) = self.state.withLock { adapterState in
            (adapterState.restClient, adapterState.sessionID)
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
        let currentSessionID = self.state.withLock { $0.sessionID }
        guard sessionID == currentSessionID else { return false }
        return self.state.withLock { $0.isRunning }
    }

    // MARK: Private

    private let discovery: OpenCodeServerDiscovery
    private let state: Mutex<AdapterState>
}

// MARK: - AdapterState

/// Mutable state for the adapter, protected by `Mutex`.
private struct AdapterState: Sendable {
    var isRunning = false
    var sessionID: String?
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
