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
        self.runningProviders = Set(self.adapters.keys)
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
        self.runningProviders.removeAll()
    }

    /// Start a single registered provider by ID.
    public func startProvider(_ id: ProviderID) async throws {
        guard let adapter = self.adapters[id] else {
            throw ProviderStartupError.notRegistered(id)
        }
        try await adapter.start()
        self.runningProviders.insert(id)
    }

    /// Stop a single registered provider by ID.
    public func stopProvider(_ id: ProviderID) async {
        guard let adapter = self.adapters[id] else { return }
        await adapter.stop()
        self.runningProviders.remove(id)
    }

    /// Whether a provider is currently running.
    public func isRunning(_ id: ProviderID) -> Bool {
        self.runningProviders.contains(id)
    }

    /// Start only the providers that are enabled in `AppSettings.enabledProviders`.
    ///
    /// Returns the IDs of providers that failed to start so callers can log/report.
    public func startEnabledProviders() async -> [ProviderID: any Error] {
        let enabled = AppSettings.enabledProviders
        var failures: [ProviderID: any Error] = [:]

        for (id, adapter) in self.adapters where enabled.contains(id) {
            do {
                try await adapter.start()
                self.runningProviders.insert(id)
            } catch {
                failures[id] = error
            }
        }

        return failures
    }

    /// Enable a provider at runtime: starts it, then persists to settings on success.
    public func enableProvider(_ id: ProviderID) async throws {
        try await self.startProvider(id)
        var enabled = AppSettings.enabledProviders
        enabled.insert(id)
        AppSettings.enabledProviders = enabled
    }

    /// Disable a provider at runtime: updates settings and stops it.
    public func disableProvider(_ id: ProviderID) async {
        var enabled = AppSettings.enabledProviders
        enabled.remove(id)
        AppSettings.enabledProviders = enabled
        await self.stopProvider(id)
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
    private var runningProviders: Set<ProviderID> = []
}
