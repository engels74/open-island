import Foundation
public import OICore
import Synchronization

// MARK: - CodexProviderAdapter

/// Top-level adapter that composes all Codex CLI components and conforms to ``ProviderAdapter``.
///
/// Owns the ``CodexAppServerClient`` (JSON-RPC communication), ``CodexEventNormalizer``
/// (event mapping), and ``CodexSessionRolloutParser`` (chat history). Merges notification
/// and server-request streams into a single ``AsyncStream<ProviderEvent>``.
public final class CodexProviderAdapter: ProviderAdapter, Sendable {
    // MARK: Lifecycle

    public init(binaryPath: String = "codex") {
        self.client = CodexAppServerClient(binaryPath: binaryPath)
        self.binaryPath = binaryPath
        self.state = Mutex(.init())
    }

    // MARK: Public

    public let providerID: ProviderID = .codex
    public let metadata: ProviderMetadata = .metadata(for: .codex)
    public let transportType: ProviderTransportType = .jsonRPC

    public func start() async throws(ProviderStartupError) {
        let alreadyRunning = self.state.withLock { $0.isRunning }
        guard !alreadyRunning else {
            throw .alreadyRunning
        }

        // 1. Verify codex binary exists on PATH
        guard Self.binaryExists(self.binaryPath) else {
            throw .binaryNotFound(self.binaryPath)
        }

        // 2. Start app-server and perform JSON-RPC handshake
        do {
            try await self.client.start()
        } catch {
            throw .jsonRPCHandshakeFailed(underlying: error)
        }

        // 3. Generate a session ID for this adapter session
        let sessionID = "codex-\(UUID().uuidString)"

        // 4. Create the merged event stream
        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
            // Event stream — preserve ordering, don't drop events.
            bufferingPolicy: .bufferingOldest(128),
        )

        // 5. Start notification processing task (detached to avoid inheriting caller
        //    isolation — prevents deadlock when stop() is called from the same context).
        let capturedClient = self.client
        let capturedSessionID = sessionID
        let notificationTask = Task.detached { [weak self] in
            for await notification in await capturedClient.notifications() {
                guard !Task.isCancelled else { break }
                self?.processNotification(notification, sessionID: capturedSessionID, continuation: continuation)
            }

            // The notification stream ending means the process terminated.
            // Reset all adapter state so start() / respondToPermission work
            // correctly if the adapter is reused after an unexpected exit.
            guard !Task.isCancelled, let self else { return }
            let wasRunning = self.state.withLock { adapterState -> Bool in
                guard adapterState.isRunning else { return false }
                adapterState.isRunning = false
                adapterState.sessionID = nil
                adapterState.eventContinuation = nil
                adapterState.eventStream = nil
                adapterState.notificationTask = nil
                adapterState.serverRequestTask = nil
                adapterState.pendingApprovals = [:]
                return true
            }
            if wasRunning {
                continuation.yield(.sessionEnded(capturedSessionID))
                continuation.finish()
            }
        }

        // 6. Start server-request processing task (detached — same rationale as above).
        let serverRequestTask = Task.detached { [weak self] in
            for await request in await capturedClient.serverRequests() {
                guard !Task.isCancelled else { break }
                self?.processServerRequest(request, sessionID: capturedSessionID, continuation: continuation)
            }
        }

        self.state.withLock { adapterState in
            adapterState.isRunning = true
            adapterState.sessionID = sessionID
            adapterState.eventStream = stream
            adapterState.eventContinuation = continuation
            adapterState.notificationTask = notificationTask
            adapterState.serverRequestTask = serverRequestTask
        }

        // Emit session started event
        continuation.yield(.sessionStarted(sessionID, cwd: "", pid: nil))
    }

    public func stop() async {
        let extracted = self.state.withLock { adapterState -> (
            continuation: AsyncStream<ProviderEvent>.Continuation?,
            sessionID: String?,
            notificationTask: Task<Void, Never>?,
            serverRequestTask: Task<Void, Never>?
        ) in
            guard adapterState.isRunning else {
                return (nil, nil, nil, nil)
            }

            let cont = adapterState.eventContinuation
            let sid = adapterState.sessionID
            let nTask = adapterState.notificationTask
            let srTask = adapterState.serverRequestTask

            adapterState.eventContinuation = nil
            adapterState.eventStream = nil
            adapterState.isRunning = false
            adapterState.sessionID = nil
            adapterState.notificationTask = nil
            adapterState.serverRequestTask = nil
            adapterState.pendingApprovals = [:]

            return (cont, sid, nTask, srTask)
        }

        // Cancel processing tasks
        extracted.notificationTask?.cancel()
        extracted.serverRequestTask?.cancel()

        // Emit session ended before stopping
        if let sid = extracted.sessionID {
            extracted.continuation?.yield(.sessionEnded(sid))
        }

        // Stop the app-server client
        await self.client.stop()

        // Finish the provider event stream
        extracted.continuation?.finish()
    }

    public func events() -> AsyncStream<ProviderEvent> {
        if let stream = state.withLock({ $0.eventStream }) {
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
        // Look up the stored JSON-RPC request ID for this permission request
        let rpcRequestID = self.state.withLock { adapterState in
            adapterState.pendingApprovals.removeValue(forKey: request.id)
        }

        guard let rpcRequestID else {
            throw CodexPermissionResponseError.noPendingApproval(requestID: request.id)
        }

        // Map PermissionDecision → CodexApprovalDecision
        let codexDecision: CodexApprovalDecision = switch decision {
        case .allow: .accept
        case .deny: .decline
        }

        let response = CodexApprovalResponse(decision: codexDecision)
        let data = try JSONEncoder().encode(response)
        let jsonValue = try JSONDecoder().decode(JSONValue.self, from: data)

        try await self.client.sendResponse(id: rpcRequestID, result: jsonValue)
    }

    public func isSessionAlive(_ sessionID: String) -> Bool {
        let currentSessionID = self.state.withLock { $0.sessionID }
        guard sessionID == currentSessionID else { return false }
        // isRunning is set to false both by stop() and by the notification
        // processing task when the underlying process terminates unexpectedly.
        return self.state.withLock { $0.isRunning }
    }

    // MARK: Private

    private let client: CodexAppServerClient
    private let binaryPath: String
    private let state: Mutex<AdapterState>

    /// Check if a binary exists on PATH using the shared ``UserPATH`` helper
    /// which augments the GUI app's minimal PATH with well-known user directories.
    private static func binaryExists(_ name: String) -> Bool {
        UserPATH.resolveInPATH(name) != nil
    }

    /// Process a JSON-RPC notification from the app-server.
    private func processNotification(
        _ notification: JSONRPCNotification,
        sessionID: SessionID,
        continuation: AsyncStream<ProviderEvent>.Continuation,
    ) {
        do {
            let events = try CodexEventNormalizer.normalize(notification, sessionID: sessionID)
            for event in events {
                continuation.yield(event)
            }
        } catch {
            NSLog("[CodexProviderAdapter] Failed to normalize notification '\(notification.method)': \(error)")
        }
    }

    /// Process a server-initiated request (approval interception).
    private func processServerRequest(
        _ request: ServerInitiatedRequest,
        sessionID: SessionID,
        continuation: AsyncStream<ProviderEvent>.Continuation,
    ) {
        do {
            let event = try CodexEventNormalizer.normalizeServerRequest(request, sessionID: sessionID)

            // Store the JSON-RPC request ID so we can respond later
            if case let .permissionRequested(_, permRequest) = event {
                self.state.withLock { adapterState in
                    adapterState.pendingApprovals[permRequest.id] = request.id
                }
            }

            let yieldResult = continuation.yield(event)

            // If the permission event was dropped (buffer full), remove the pending approval
            // entry so state doesn't leak — the UI will never see the prompt to respond.
            if case .dropped = yieldResult, case let .permissionRequested(_, permRequest) = event {
                _ = self.state.withLock { adapterState in
                    adapterState.pendingApprovals.removeValue(forKey: permRequest.id)
                }
                NSLog("[CodexProviderAdapter] Warning: dropped permissionRequested event for request '\(permRequest.id)' — buffer full")
            }
        } catch {
            NSLog("[CodexProviderAdapter] Failed to normalize server request '\(request.method)': \(error)")
        }
    }
}

// MARK: - AdapterState

/// Mutable state for the adapter, protected by `Mutex`.
private struct AdapterState: Sendable {
    var isRunning = false
    var sessionID: String?
    var eventStream: AsyncStream<ProviderEvent>?
    var eventContinuation: AsyncStream<ProviderEvent>.Continuation?
    var notificationTask: Task<Void, Never>?
    var serverRequestTask: Task<Void, Never>?
    /// Maps permission request IDs → JSON-RPC request IDs for approval responses.
    var pendingApprovals: [String: JSONRPCRequestID] = [:]
}

// MARK: - CodexPermissionResponseError

/// Errors from responding to a Codex permission request.
package enum CodexPermissionResponseError: Error, Sendable {
    /// No pending approval request found for the given permission request ID.
    case noPendingApproval(requestID: String)
}
