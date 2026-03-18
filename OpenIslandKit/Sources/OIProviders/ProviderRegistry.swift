public import OICore

/// Central registry managing all provider adapters.
///
/// Starts/stops adapters, provides lookup by ID, and merges
/// all provider event streams into a single `AsyncStream`.
public actor ProviderRegistry {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    /// All registered provider IDs.
    public var registeredProviders: [ProviderID] {
        Array(self.adapters.keys)
    }

    /// Register a provider adapter.
    public func register(_ adapter: any ProviderAdapter) {
        self.adapters[adapter.providerID] = adapter
    }

    /// Look up an adapter by provider ID.
    public func adapter(for id: ProviderID) -> (any ProviderAdapter)? {
        self.adapters[id]
    }

    /// Start all registered adapters concurrently.
    public func startAll() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for adapter in self.adapters.values {
                group.addTask {
                    try await adapter.start()
                }
            }
            try await group.waitForAll()
        }
    }

    /// Stop all registered adapters concurrently.
    public func stopAll() async {
        await withTaskGroup(of: Void.self) { group in
            for adapter in self.adapters.values {
                group.addTask {
                    await adapter.stop()
                }
            }
        }
    }

    /// Merge all provider event streams into a single stream.
    ///
    /// Uses `withThrowingDiscardingTaskGroup` (SE-0381) for long-running
    /// event forwarding — child task results are automatically discarded
    /// to prevent memory leaks.
    public func mergedEvents() -> AsyncStream<ProviderEvent> {
        let currentAdapters = Array(adapters.values)
        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
            // Merged event stream — preserve ordering across all providers.
            bufferingPolicy: .bufferingOldest(128),
        )
        let task = Task {
            try await withThrowingDiscardingTaskGroup { group in
                for adapter in currentAdapters {
                    group.addTask {
                        for await event in adapter.events() {
                            continuation.yield(event)
                        }
                    }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    // MARK: Private

    private var adapters: [ProviderID: any ProviderAdapter] = [:]
}
