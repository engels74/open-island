import Foundation
@testable import OICore
@testable import OIProviders
@testable import OIState
import Testing

// MARK: - SessionStoreTests

struct SessionStoreTests {
    // MARK: Internal

    // MARK: - Event Processing: Session Lifecycle

    @Test
    func `creates session on sessionStarted event`() async {
        let store = await storeWithSession()
        let session = await store.session(for: "s1")
        #expect(session != nil)
        #expect(session?.phase == .idle)
        #expect(session?.projectName == "project")
        #expect(session?.cwd == "/tmp/project")
        #expect(session?.pid == 123)
    }

    @Test
    func `transitions to .processing on processingStarted`() async {
        let store = await storeWithSession()
        await store.process(.providerEvent(.processingStarted("s1")))
        let session = await store.session(for: "s1")
        #expect(session?.phase == .processing)
    }

    @Test
    func `transitions to .waitingForInput`() async {
        let store = await storeWithSession()
        await store.process(.providerEvent(.processingStarted("s1")))
        await store.process(.providerEvent(.waitingForInput("s1")))
        let session = await store.session(for: "s1")
        #expect(session?.phase == .waitingForInput)
    }

    @Test
    func `transitions to .waitingForApproval on permissionRequested`() async {
        let store = await storeWithSession()
        await store.process(.providerEvent(.processingStarted("s1")))
        let request = PermissionRequest(
            id: "req1",
            toolName: "Bash",
            timestamp: Date(),
        )
        await store.process(.providerEvent(.permissionRequested("s1", request)))
        let session = await store.session(for: "s1")
        // SessionPhase.== compares by case only (ignores associated value)
        #expect(session?.phase == .waitingForApproval(PermissionContext(
            toolUseID: "", toolName: "", timestamp: .distantPast,
        )))
    }

    @Test
    func `transitions to .compacting`() async {
        let store = await storeWithSession()
        await store.process(.providerEvent(.processingStarted("s1")))
        await store.process(.providerEvent(.compacting("s1")))
        let session = await store.session(for: "s1")
        #expect(session?.phase == .compacting)
    }

    @Test
    func `compacting transitions to .processing on processingStarted`() async {
        let store = await storeWithSession()
        await store.process(.providerEvent(.processingStarted("s1")))
        await store.process(.providerEvent(.compacting("s1")))
        #expect(await store.session(for: "s1")?.phase == .compacting)
        await store.process(.providerEvent(.processingStarted("s1")))
        #expect(await store.session(for: "s1")?.phase == .processing)
    }

    @Test
    func `compacting transitions to .processing on userPromptSubmitted`() async {
        let store = await storeWithSession()
        await store.process(.providerEvent(.processingStarted("s1")))
        await store.process(.providerEvent(.compacting("s1")))
        #expect(await store.session(for: "s1")?.phase == .compacting)
        await store.process(.providerEvent(.userPromptSubmitted("s1")))
        #expect(await store.session(for: "s1")?.phase == .processing)
    }

    @Test
    func `compacting transitions to .ended on sessionEnded`() async {
        let store = await storeWithSession()
        await store.process(.providerEvent(.processingStarted("s1")))
        await store.process(.providerEvent(.compacting("s1")))
        #expect(await store.session(for: "s1")?.phase == .compacting)
        await store.process(.providerEvent(.sessionEnded("s1")))
        #expect(await store.session(for: "s1")?.phase == .ended)
    }

    @Test
    func `transitions to .ended on sessionEnded`() async {
        let store = await storeWithSession()
        await store.process(.providerEvent(.sessionEnded("s1")))
        let session = await store.session(for: "s1")
        #expect(session?.phase == .ended)
    }

    // MARK: - Event Processing: Permission Actions

    @Test
    func `permissionApproved transitions to .processing`() async {
        let store = await storeWithSession()
        await store.process(.providerEvent(.processingStarted("s1")))
        let request = PermissionRequest(
            id: "req1",
            toolName: "Bash",
            timestamp: Date(),
        )
        await store.process(.providerEvent(.permissionRequested("s1", request)))
        await store.process(.permissionApproved("s1", requestID: "req1"))
        let session = await store.session(for: "s1")
        #expect(session?.phase == .processing)
    }

    @Test
    func `permissionDenied transitions to .processing`() async {
        let store = await storeWithSession()
        await store.process(.providerEvent(.processingStarted("s1")))
        let request = PermissionRequest(
            id: "req1",
            toolName: "Bash",
            timestamp: Date(),
        )
        await store.process(.providerEvent(.permissionRequested("s1", request)))
        await store.process(.permissionDenied("s1", requestID: "req1", reason: "too risky"))
        let session = await store.session(for: "s1")
        #expect(session?.phase == .processing)
    }

    @Test
    func `archiveSession transitions to .ended`() async {
        let store = await storeWithSession()
        await store.process(.archiveSession("s1"))
        let session = await store.session(for: "s1")
        #expect(session?.phase == .ended)
    }

    // MARK: - Transition Validation

    @Test
    func `invalid transition from idle to waitingForInput is rejected`() async {
        let store = await storeWithSession()
        // idle → waitingForInput is invalid
        await store.process(.providerEvent(.waitingForInput("s1")))
        let session = await store.session(for: "s1")
        #expect(session?.phase == .idle)
    }

    @Test
    func `event for unknown session is ignored`() async {
        let store = SessionStore()
        await store.process(.providerEvent(.processingStarted("nonexistent")))
        let session = await store.session(for: "nonexistent")
        #expect(session == nil)
    }

    // MARK: - Multi-Subscriber Broadcast

    @Test
    func `multiple subscribers receive the same state snapshot`() async throws {
        let store = await storeWithSession()

        // Set up two subscriber streams
        let stream1 = await store.sessionsStream()
        let stream2 = await store.sessionsStream()

        // Both streams receive an initial snapshot immediately; then a broadcast on processingStarted
        await store.process(.providerEvent(.processingStarted("s1")))

        // Collect the latest value from each stream
        var iterator1 = stream1.makeAsyncIterator()
        var iterator2 = stream2.makeAsyncIterator()

        // The first yield is the initial snapshot; skip to get the post-event snapshot
        // With bufferingNewest(1), we may get only the latest
        let snapshot1 = await iterator1.next()
        let snapshot2 = await iterator2.next()

        let s1 = try #require(snapshot1)
        let s2 = try #require(snapshot2)

        #expect(s1.count == s2.count)
        #expect(s1.first?.phase == s2.first?.phase)
    }

    // MARK: - Zombie Session Cleanup

    @Test
    func `health check transitions zombie sessions to .ended`() async throws {
        let store = await storeWithSession()

        let mock = MockProviderAdapter(providerID: .claude, alive: false)
        let registry = ProviderRegistry()
        await registry.register(mock)

        await store.startHealthCheck(registry: registry)

        // Health check fires every 3s; wait long enough for it to run
        try await Task.sleep(for: .seconds(4))

        await store.stopHealthCheck()

        let session = await store.session(for: "s1")
        #expect(session?.phase == .ended)
    }

    @Test
    func `health check keeps alive sessions untouched`() async throws {
        let store = await storeWithSession()

        let mock = MockProviderAdapter(providerID: .claude, alive: true)
        let registry = ProviderRegistry()
        await registry.register(mock)

        await store.startHealthCheck(registry: registry)
        try await Task.sleep(for: .seconds(4))
        await store.stopHealthCheck()

        let session = await store.session(for: "s1")
        #expect(session?.phase == .idle)
    }

    // MARK: - Audit Trail Ring Buffer

    @Test
    func `store remains consistent after >100 events (audit buffer wraps)`() async {
        let store = await storeWithSession()

        // Process 150 events to force the 100-element ring buffer to wrap
        for i in 0 ..< 150 {
            await store.process(.providerEvent(.notification("s1", message: "event-\(i)")))
        }

        // Verify the session is still intact and functional after buffer wrap
        let session = await store.session(for: "s1")
        #expect(session != nil)
        #expect(session?.phase == .idle)

        await store.process(.providerEvent(.processingStarted("s1")))
        let updated = await store.session(for: "s1")
        #expect(updated?.phase == .processing)
    }

    // MARK: - Concurrent Event Processing

    @Test
    func `concurrent events do not cause data corruption`() async {
        let store = SessionStore()

        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 20 {
                group.addTask {
                    await store.process(
                        .providerEvent(.sessionStarted("s\(i)", cwd: "/tmp/p\(i)", pid: Int32(i))),
                    )
                }
            }
        }

        let sessions = await store.currentSessions
        #expect(sessions.count == 20)

        for session in sessions {
            #expect(session.phase == .idle)
        }
    }

    @Test
    func `concurrent transitions on the same session are serialized`() async {
        let store = await storeWithSession()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 10 {
                group.addTask {
                    await store.process(.providerEvent(.processingStarted("s1")))
                }
            }
        }

        let session = await store.session(for: "s1")
        #expect(session?.phase == .processing)
    }

    // MARK: - Chat & Token Updates

    @Test
    func `chatUpdated replaces chat items`() async {
        let store = await storeWithSession()

        let items = [
            ChatHistoryItem(id: "c1", timestamp: Date(), type: .user, content: "Hello"),
            ChatHistoryItem(id: "c2", timestamp: Date(), type: .assistant, content: "Hi there"),
        ]
        await store.process(.providerEvent(.chatUpdated("s1", items)))

        let session = await store.session(for: "s1")
        #expect(session?.chatItems.count == 2)
    }

    @Test
    func `tokenUsage updates session snapshot`() async {
        let store = await storeWithSession()

        await store.process(.providerEvent(.tokenUsage("s1", promptTokens: 100, completionTokens: 50, totalTokens: 150)))

        let session = await store.session(for: "s1")
        #expect(session?.tokenUsage?.totalTokens == 150)
    }

    // MARK: - currentSessions Ordering

    @Test
    func `currentSessions returns sessions sorted by most recent activity`() async throws {
        let store = SessionStore()

        await store.process(.providerEvent(.sessionStarted("s1", cwd: "/tmp/a", pid: 1)))
        // Small delay to ensure ordering
        try await Task.sleep(for: .milliseconds(10))
        await store.process(.providerEvent(.sessionStarted("s2", cwd: "/tmp/b", pid: 2)))

        let sessions = await store.currentSessions
        #expect(sessions.count == 2)
        // s2 was created more recently
        #expect(sessions.first?.id == "s2")
    }

    // MARK: Private

    // MARK: - Helpers

    /// Create a session by sending a `.sessionStarted` event and return the store.
    private func storeWithSession(
        id: String = "s1",
        cwd: String = "/tmp/project",
        pid: Int32? = 123,
    ) async -> SessionStore {
        let store = SessionStore()
        await store.process(.providerEvent(.sessionStarted(id, cwd: cwd, pid: pid)))
        return store
    }
}
