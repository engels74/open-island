import Foundation
package import OICore
import Synchronization

// MARK: - AdapterState

private struct AdapterState: Sendable {
    var isRunning = false
    var eventStream: AsyncStream<ProviderEvent>?
    var eventContinuation: AsyncStream<ProviderEvent>.Continuation?
    var simulationTask: Task<Void, Never>?
    var activeSessions: Set<String> = []
}

// MARK: - ExampleProviderAdapter

/// Emits simulated provider events on a timer for UI testing and as a
/// template for new provider implementations.
package final class ExampleProviderAdapter: ProviderAdapter, Sendable {
    // MARK: Lifecycle

    package init(eventInterval: Duration = .seconds(1)) {
        self.eventInterval = eventInterval
        self.state = Mutex(.init())
    }

    // MARK: Package

    package let providerID: ProviderID = .example
    package let metadata: ProviderMetadata = .metadata(for: .example)
    package let transportType: ProviderTransportType = .hookSocket

    package func start() async throws(ProviderStartupError) {
        let alreadyRunning = self.state.withLock { $0.isRunning }
        guard !alreadyRunning else {
            throw .alreadyRunning
        }

        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(128),
        )

        let interval = self.eventInterval
        let adapter = self

        // Detached to avoid inheriting caller's actor isolation.
        let simulationTask: Task<Void, Never> = Task.detached { [weak adapter] in
            await adapter?.runSimulation(continuation: continuation, interval: interval)
        }

        self.state.withLock { state in
            state.isRunning = true
            state.eventStream = stream
            state.eventContinuation = continuation
            state.simulationTask = simulationTask
        }
    }

    package func stop() async {
        // Extract before finishing — finish() triggers onTermination synchronously.
        let (continuation, simulationTask) = self.state.withLock { state -> (AsyncStream<ProviderEvent>.Continuation?, Task<Void, Never>?) in
            guard state.isRunning else { return (nil, nil) }

            let cont = state.eventContinuation
            let task = state.simulationTask
            state.eventContinuation = nil
            state.eventStream = nil
            state.simulationTask = nil
            state.isRunning = false
            state.activeSessions = []
            return (cont, task)
        }

        simulationTask?.cancel()
        continuation?.finish()
    }

    package func events() -> AsyncStream<ProviderEvent> {
        if let stream = self.state.withLock({ $0.eventStream }) {
            return stream
        }
        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream()
        continuation.finish()
        return stream
    }

    package func respondToPermission(
        _ request: PermissionRequest,
        decision: PermissionDecision,
    ) async throws {
        // No actual CLI process to respond to — just log.
        NSLog("[ExampleProviderAdapter] Permission \(request.id): \(decision)")
    }

    package func isSessionAlive(_ sessionID: String) -> Bool {
        self.state.withLock { $0.activeSessions.contains(sessionID) }
    }

    // MARK: Private

    private let eventInterval: Duration
    private let state: Mutex<AdapterState>

    private func runSimulation(
        continuation: AsyncStream<ProviderEvent>.Continuation,
        interval: Duration,
    ) async {
        let sessionID = "example-\(UUID().uuidString.prefix(8))"
        let toolID = "tool-\(UUID().uuidString.prefix(8))"
        let permissionID = "perm-\(UUID().uuidString.prefix(8))"

        _ = self.state.withLock { $0.activeSessions.insert(sessionID) }

        let events: [ProviderEvent] = [
            .sessionStarted(sessionID, providerID: .example, cwd: "/tmp/example-project", pid: nil),
            .processingStarted(sessionID),
            .modelResponse(sessionID, textDelta: "Let me analyze the project structure..."),
            .toolStarted(
                sessionID,
                ToolEvent(id: toolID, name: "Read", input: nil, startedAt: .now),
            ),
            .toolCompleted(
                sessionID,
                ToolEvent(id: toolID, name: "Read", input: nil, startedAt: .now),
                ToolResult(isSuccess: true),
            ),
            .permissionRequested(
                sessionID,
                PermissionRequest(
                    id: permissionID,
                    toolName: "Write",
                    timestamp: .now,
                ),
            ),
            .modelResponse(sessionID, textDelta: "I've completed the analysis."),
            .waitingForInput(sessionID),
            .sessionEnded(sessionID),
        ]

        for event in events {
            guard !Task.isCancelled else { break }

            do {
                try await Task.sleep(for: interval)
            } catch {
                break
            }

            continuation.yield(event)
        }

        _ = self.state.withLock { $0.activeSessions.remove(sessionID) }

        continuation.finish()

        // Reset adapter state so start() can be called again without
        // requiring an explicit stop() after natural simulation completion.
        self.state.withLock { state in
            state.isRunning = false
            state.eventContinuation = nil
            state.eventStream = nil
            state.simulationTask = nil
        }
    }
}
