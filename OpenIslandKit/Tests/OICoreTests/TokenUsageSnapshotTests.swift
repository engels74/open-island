import Foundation
@testable import OICore
import Testing

struct TokenUsageSnapshotTests {
    @Test
    func `Equatable with all fields populated`() {
        let timestamp = Date.now
        let lhs = TokenUsageSnapshot(promptTokens: 100, completionTokens: 50, totalTokens: 150, timestamp: timestamp)
        let rhs = TokenUsageSnapshot(promptTokens: 100, completionTokens: 50, totalTokens: 150, timestamp: timestamp)
        #expect(lhs == rhs)
    }

    @Test
    func `Equatable with nil fields`() {
        let timestamp = Date.now
        let lhs = TokenUsageSnapshot(promptTokens: nil, completionTokens: nil, totalTokens: nil, timestamp: timestamp)
        let rhs = TokenUsageSnapshot(promptTokens: nil, completionTokens: nil, totalTokens: nil, timestamp: timestamp)
        #expect(lhs == rhs)
    }

    @Test
    func `Inequality on different values`() {
        let timestamp = Date.now
        let lhs = TokenUsageSnapshot(promptTokens: 100, completionTokens: nil, totalTokens: nil, timestamp: timestamp)
        let rhs = TokenUsageSnapshot(promptTokens: 200, completionTokens: nil, totalTokens: nil, timestamp: timestamp)
        #expect(lhs != rhs)
    }

    @Test
    func `Inequality on different timestamps`() {
        let lhs = TokenUsageSnapshot(promptTokens: 100, timestamp: Date(timeIntervalSince1970: 1000))
        let rhs = TokenUsageSnapshot(promptTokens: 100, timestamp: Date(timeIntervalSince1970: 2000))
        #expect(lhs != rhs)
    }

    @Test
    func `Default nil parameters`() {
        let snap = TokenUsageSnapshot(timestamp: .now)
        #expect(snap.promptTokens == nil)
        #expect(snap.completionTokens == nil)
        #expect(snap.totalTokens == nil)
    }
}
