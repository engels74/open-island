import Foundation
public import OICore
import Synchronization

// MARK: - CodexProviderAdapter

/// Top-level adapter composing all Codex CLI components, conforming to ``ProviderAdapter``.
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

        guard Self.binaryExists(self.binaryPath) else {
            throw .binaryNotFound(self.binaryPath)
        }

        do {
            try await self.client.start()
        } catch {
            throw .jsonRPCHandshakeFailed(underlying: error)
        }

        let sessionID = "codex-\(UUID().uuidString)"

        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(128),
        )

        // Detached to avoid inheriting caller isolation —
        // prevents deadlock when stop() is called from the same context.
        let capturedClient = self.client
        let capturedSessionID = sessionID
        let notificationTask = Task.detached { [weak self] in
            for await notification in await capturedClient.notifications() {
                guard !Task.isCancelled else { break }
                self?.processNotification(notification, sessionID: capturedSessionID, continuation: continuation)
            }

            // Stream ended = process terminated. Reset state so start() works
            // if the adapter is reused after an unexpected exit.
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

        continuation.yield(.sessionStarted(sessionID, providerID: .codex, cwd: "", pid: nil))
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

        extracted.notificationTask?.cancel()
        extracted.serverRequestTask?.cancel()

        if let sid = extracted.sessionID {
            extracted.continuation?.yield(.sessionEnded(sid))
        }

        await self.client.stop()
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
        let rpcRequestID = self.state.withLock { adapterState in
            adapterState.pendingApprovals.removeValue(forKey: request.id)
        }

        guard let rpcRequestID else {
            throw CodexPermissionResponseError.noPendingApproval(requestID: request.id)
        }

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

    /// Uses ``UserPATH`` to augment the GUI app's minimal PATH with
    /// well-known user directories (Homebrew, nvm, etc.).
    private static func binaryExists(_ name: String) -> Bool {
        UserPATH.resolveInPATH(name) != nil
    }

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

    private func processServerRequest(
        _ request: ServerInitiatedRequest,
        sessionID: SessionID,
        continuation: AsyncStream<ProviderEvent>.Continuation,
    ) {
        do {
            let event = try CodexEventNormalizer.normalizeServerRequest(request, sessionID: sessionID)

            if case let .permissionRequested(_, permRequest) = event {
                self.state.withLock { adapterState in
                    adapterState.pendingApprovals[permRequest.id] = request.id
                }
            }

            let yieldResult = continuation.yield(event)

            // Remove pending approval if dropped — the UI will never see the prompt.
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

private struct AdapterState: Sendable {
    var isRunning = false
    var sessionID: String?
    var eventStream: AsyncStream<ProviderEvent>?
    var eventContinuation: AsyncStream<ProviderEvent>.Continuation?
    var notificationTask: Task<Void, Never>?
    var serverRequestTask: Task<Void, Never>?
    var pendingApprovals: [String: JSONRPCRequestID] = [:]
}

// MARK: - CodexPermissionResponseError

package enum CodexPermissionResponseError: Error, Sendable {
    case noPendingApproval(requestID: String)
}
