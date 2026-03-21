public import OICore

/// Central registry managing all provider adapters.
public actor ProviderRegistry {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public var registeredProviders: [ProviderID] {
        Array(self.adapters.keys)
    }

    public func register(_ adapter: any ProviderAdapter) {
        self.adapters[adapter.providerID] = adapter
    }

    public func adapter(for id: ProviderID) -> (any ProviderAdapter)? {
        self.adapters[id]
    }

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

    public func startProvider(_ id: ProviderID) async throws {
        guard let adapter = self.adapters[id] else {
            throw ProviderStartupError.notRegistered(id)
        }
        try await adapter.start()
        self.runningProviders.insert(id)
    }

    public func stopProvider(_ id: ProviderID) async {
        guard let adapter = self.adapters[id] else { return }
        await adapter.stop()
        self.runningProviders.remove(id)
    }

    public func isRunning(_ id: ProviderID) -> Bool {
        self.runningProviders.contains(id)
    }

    /// Returns the IDs of providers that failed to start.
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

    public func enableProvider(_ id: ProviderID) async throws {
        try await self.startProvider(id)
        var enabled = AppSettings.enabledProviders
        enabled.insert(id)
        AppSettings.enabledProviders = enabled
    }

    public func disableProvider(_ id: ProviderID) async {
        var enabled = AppSettings.enabledProviders
        enabled.remove(id)
        AppSettings.enabledProviders = enabled
        await self.stopProvider(id)
    }

    /// Uses `withThrowingDiscardingTaskGroup` (SE-0381) — child task results
    /// are automatically discarded to prevent memory leaks.
    public func mergedEvents() -> AsyncStream<ProviderEvent> {
        let currentAdapters = Array(adapters.values)
        let (stream, continuation) = AsyncStream<ProviderEvent>.makeStream(
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
