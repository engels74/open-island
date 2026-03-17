import Foundation
package import OICore
import Synchronization

// MARK: - AdapterState

/// Mutable state for the adapter, protected by `Mutex`.
///
/// Mirrors the state shape used by real adapters (Claude, Gemini, etc.) so that
/// this example serves as a faithful template for new provider implementations.
private struct AdapterState: Sendable {
    var isRunning = false
    var eventStream: AsyncStream<ProviderEvent>?
    var eventContinuation: AsyncStream<ProviderEvent>.Continuation?
    var simulationTask: Task<Void, Never>?

    /// Track active session IDs so `isSessionAlive` can give a meaningful answer.
    var activeSessions: Set<String> = []
}

// MARK: - ExampleProviderAdapter

/// A self-contained adapter that emits simulated provider events on a timer.
///
/// Intended for three audiences:
/// 1. **New contributors** — demonstrates every `ProviderAdapter` requirement
///    with the minimal amount of ceremony, free from transport-layer complexity
///    (no sockets, no JSON-RPC, no HTTP/SSE).
/// 2. **UI developers** — produces a realistic event sequence for testing
///    session views, permission dialogs, and phase transitions without needing
///    an actual CLI process running.
/// 3. **Integration tests** — can be registered in `ProviderRegistry` alongside
///    real adapters to validate the merged-event pipeline end-to-end.
///
/// The simulation walks through the full session lifecycle:
///   sessionStarted -> processingStarted -> toolStarted -> toolCompleted
///   -> permissionRequested -> waitingForInput -> sessionEnded
///
/// Each event is separated by a short delay so consumers can observe
/// phase transitions in real time.
package final class ExampleProviderAdapter: ProviderAdapter, Sendable {
    // MARK: Lifecycle

    /// - Parameter eventInterval: Delay between simulated events.
    ///   Defaults to 1 second — fast enough to feel responsive, slow enough
    ///   to visually distinguish each phase in the UI.
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

        // Real adapters open a socket or HTTP connection here.
        // We skip that entirely — the only "transport" is a Task that
        // yields synthetic events on a timer.

        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
            bufferingPolicy: .bufferingOldest(128),
        )

        let interval = self.eventInterval
        let adapter = self

        // Detached so we don't inherit the caller's actor isolation,
        // matching the pattern established by ClaudeProviderAdapter.
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
        // Extract mutable references before finishing to avoid re-entrant
        // Mutex access — `finish()` can trigger `onTermination` synchronously.
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
        // Not started — return an immediately-finished empty stream,
        // same convention as the real adapters.
        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream()
        continuation.finish()
        return stream
    }

    package func respondToPermission(
        _ request: PermissionRequest,
        decision: PermissionDecision,
    ) async throws {
        // Real adapters send the decision back over their transport layer.
        // Here we just log it — the example has no actual CLI process waiting
        // for a response, so there's nothing to unblock.
        NSLog("[ExampleProviderAdapter] Permission \(request.id): \(decision)")
    }

    package func isSessionAlive(_ sessionID: String) -> Bool {
        // Check against our tracked set rather than always returning true.
        // This lets the health-check zombie detection work correctly if the
        // example adapter is registered alongside real ones.
        self.state.withLock { $0.activeSessions.contains(sessionID) }
    }

    // MARK: Private

    private let eventInterval: Duration
    private let state: Mutex<AdapterState>

    /// Walk through a complete session lifecycle, yielding each event with
    /// a delay so consumers can observe the phase transitions in sequence.
    ///
    /// The event ordering mirrors what a real provider produces:
    /// 1. Session starts (idle -> processing transition)
    /// 2. Model begins processing
    /// 3. A tool runs (e.g., file read)
    /// 4. A permission-gated tool is attempted (triggers approval UI)
    /// 5. Model finishes and waits for next user input
    /// 6. Session ends
    private func runSimulation(
        continuation: AsyncStream<ProviderEvent>.Continuation,
        interval: Duration,
    ) async {
        let sessionID = "example-\(UUID().uuidString.prefix(8))"
        let toolID = "tool-\(UUID().uuidString.prefix(8))"
        let permissionID = "perm-\(UUID().uuidString.prefix(8))"

        // Register the session so isSessionAlive returns true during the simulation.
        _ = self.state.withLock { $0.activeSessions.insert(sessionID) }

        let events: [ProviderEvent] = [
            .sessionStarted(sessionID, cwd: "/tmp/example-project", pid: nil),
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
                // Cancellation — exit the loop cleanly.
                break
            }

            continuation.yield(event)
        }

        // Deregister the session after the lifecycle completes.
        _ = self.state.withLock { $0.activeSessions.remove(sessionID) }

        continuation.finish()
    }
}
