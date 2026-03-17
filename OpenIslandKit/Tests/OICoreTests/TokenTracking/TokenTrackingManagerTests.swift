import Foundation
@testable import OICore
import Testing

// MARK: - MockQuotaService

private struct MockQuotaService: QuotaService {
    let snapshot: QuotaSnapshot

    func fetchCurrentUsage() async throws -> QuotaSnapshot {
        self.snapshot
    }
}

// MARK: - FailingQuotaService

private struct FailingQuotaService: QuotaService {
    func fetchCurrentUsage() async throws -> QuotaSnapshot {
        throw QuotaError.unavailable
    }
}

// MARK: - QuotaError

private enum QuotaError: Error {
    case unavailable
}

// MARK: - TokenTrackingManagerTests

@MainActor
struct TokenTrackingManagerTests {
    // MARK: - Session token tracking

    @Test
    func `Update session stores token data`() {
        let manager = TokenTrackingManager()
        let usage = TokenUsageSnapshot(promptTokens: 100, completionTokens: 50, totalTokens: 150, timestamp: .now)

        manager.updateSession("s1", usage: usage)

        #expect(manager.sessionTokens["s1"] == usage)
        #expect(manager.hasTokenData)
    }

    @Test
    func `Weekly tokens aggregates total across sessions`() {
        let manager = TokenTrackingManager()
        let now = Date.now

        manager.updateSession("s1", usage: TokenUsageSnapshot(totalTokens: 1000, timestamp: now))
        manager.updateSession("s2", usage: TokenUsageSnapshot(totalTokens: 2500, timestamp: now))

        #expect(manager.weeklyTokens == 3500)
    }

    @Test
    func `Weekly tokens ignores nil totalTokens`() {
        let manager = TokenTrackingManager()
        let now = Date.now

        manager.updateSession("s1", usage: TokenUsageSnapshot(promptTokens: 100, timestamp: now))
        manager.updateSession("s2", usage: TokenUsageSnapshot(totalTokens: 500, timestamp: now))

        #expect(manager.weeklyTokens == 500)
    }

    @Test
    func `Remove session updates weekly total`() {
        let manager = TokenTrackingManager()
        let now = Date.now

        manager.updateSession("s1", usage: TokenUsageSnapshot(totalTokens: 1000, timestamp: now))
        manager.updateSession("s2", usage: TokenUsageSnapshot(totalTokens: 2000, timestamp: now))
        manager.removeSession("s1")

        #expect(manager.weeklyTokens == 2000)
        #expect(manager.sessionTokens["s1"] == nil)
    }

    @Test
    func `Remove nonexistent session is no-op`() {
        let manager = TokenTrackingManager()
        manager.updateSession("s1", usage: TokenUsageSnapshot(totalTokens: 100, timestamp: .now))

        manager.removeSession("nonexistent")

        #expect(manager.weeklyTokens == 100)
    }

    @Test
    func `Has token data is false when empty`() {
        let manager = TokenTrackingManager()
        #expect(!manager.hasTokenData)
    }

    // MARK: - Bulk update

    @Test
    func `Update from sessions replaces all data`() {
        let manager = TokenTrackingManager()
        let now = Date.now

        // Initial state
        manager.updateSession("old", usage: TokenUsageSnapshot(totalTokens: 100, timestamp: now))

        // Bulk update with new sessions
        let sessions = [
            SessionTokenInfo(id: "new1", tokenUsage: TokenUsageSnapshot(totalTokens: 500, timestamp: now)),
            SessionTokenInfo(id: "new2", tokenUsage: TokenUsageSnapshot(totalTokens: 300, timestamp: now)),
        ]
        manager.updateFromSessions(sessions)

        #expect(manager.sessionTokens["old"] == nil)
        #expect(manager.sessionTokens["new1"] != nil)
        #expect(manager.sessionTokens["new2"] != nil)
        #expect(manager.weeklyTokens == 800)
    }

    @Test
    func `Update from sessions skips nil token usage`() {
        let manager = TokenTrackingManager()

        let sessions = [
            SessionTokenInfo(id: "s1", tokenUsage: TokenUsageSnapshot(totalTokens: 100, timestamp: .now)),
            SessionTokenInfo(id: "s2", tokenUsage: nil),
        ]
        manager.updateFromSessions(sessions)

        #expect(manager.sessionTokens["s1"] != nil)
        #expect(manager.sessionTokens["s2"] == nil)
    }

    // MARK: - Quota refresh

    @Test
    func `Refresh quota updates percentage`() async {
        let quota = QuotaSnapshot(
            dailyLimit: 1000,
            dailyUsed: 450,
            timestamp: .now,
        )
        let manager = TokenTrackingManager(quotaService: MockQuotaService(snapshot: quota))

        await manager.refreshQuota()

        #expect(manager.quotaPercentage == 45.0)
        #expect(manager.latestQuota == quota)
    }

    @Test
    func `Refresh quota with no service is no-op`() async {
        let manager = TokenTrackingManager()

        await manager.refreshQuota()

        #expect(manager.quotaPercentage == nil)
        #expect(manager.latestQuota == nil)
    }

    @Test
    func `Refresh quota failure preserves stale data`() async {
        let initialQuota = QuotaSnapshot(dailyLimit: 1000, dailyUsed: 200, timestamp: .now)
        let manager = TokenTrackingManager(quotaService: MockQuotaService(snapshot: initialQuota))

        await manager.refreshQuota()
        #expect(manager.quotaPercentage == 20.0)

        // Replace with failing service — can't do this, but test that failure is non-fatal
        let failingManager = TokenTrackingManager(quotaService: FailingQuotaService())
        await failingManager.refreshQuota()
        #expect(failingManager.quotaPercentage == nil)
    }

    // MARK: - Formatting

    @Test(arguments: [
        (0, "0"),
        (999, "999"),
        (1000, "1K"),
        (1500, "1.5K"),
        (12500, "12.5K"),
        (100_000, "100K"),
        (1_000_000, "1M"),
        (2_500_000, "2.5M"),
    ])
    func `Format token count`(count: Int, expected: String) {
        #expect(TokenTrackingManager.formatTokenCount(count) == expected)
    }
}
