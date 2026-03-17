import Foundation
@testable import OICore
import Testing

struct QuotaSnapshotTests {
    @Test
    func `Utilization fraction from daily limit`() {
        let snapshot = QuotaSnapshot(
            dailyLimit: 1000,
            dailyUsed: 450,
            timestamp: .now,
        )
        #expect(snapshot.utilizationFraction == 0.45)
    }

    @Test
    func `Utilization fraction from weekly limit when no daily`() {
        let snapshot = QuotaSnapshot(
            weeklyLimit: 10000,
            weeklyUsed: 7500,
            timestamp: .now,
        )
        #expect(snapshot.utilizationFraction == 0.75)
    }

    @Test
    func `Daily limit preferred over weekly`() {
        let snapshot = QuotaSnapshot(
            dailyLimit: 100,
            dailyUsed: 50,
            weeklyLimit: 1000,
            weeklyUsed: 900,
            timestamp: .now,
        )
        // Should use daily (50/100 = 0.5), not weekly (900/1000 = 0.9)
        #expect(snapshot.utilizationFraction == 0.5)
    }

    @Test
    func `Utilization fraction capped at 1`() {
        let snapshot = QuotaSnapshot(
            dailyLimit: 100,
            dailyUsed: 200,
            timestamp: .now,
        )
        #expect(snapshot.utilizationFraction == 1.0)
    }

    @Test
    func `Utilization fraction nil when no limits`() {
        let snapshot = QuotaSnapshot(timestamp: .now)
        #expect(snapshot.utilizationFraction == nil)
    }

    @Test
    func `Utilization fraction nil when limit is zero`() {
        let snapshot = QuotaSnapshot(
            dailyLimit: 0,
            dailyUsed: 100,
            timestamp: .now,
        )
        // Zero limit with no weekly fallback → nil
        #expect(snapshot.utilizationFraction == nil)
    }

    @Test
    func `Equatable with matching fields`() {
        let ts = Date.now
        let lhs = QuotaSnapshot(dailyLimit: 1000, dailyUsed: 500, resetTime: ts, timestamp: ts)
        let rhs = QuotaSnapshot(dailyLimit: 1000, dailyUsed: 500, resetTime: ts, timestamp: ts)
        #expect(lhs == rhs)
    }

    @Test
    func `Inequality on different values`() {
        let ts = Date.now
        let lhs = QuotaSnapshot(dailyLimit: 1000, dailyUsed: 500, timestamp: ts)
        let rhs = QuotaSnapshot(dailyLimit: 1000, dailyUsed: 600, timestamp: ts)
        #expect(lhs != rhs)
    }
}
