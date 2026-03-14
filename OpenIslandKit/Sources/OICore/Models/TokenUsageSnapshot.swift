package import Foundation

/// A point-in-time snapshot of token usage for a session.
package struct TokenUsageSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    package init(
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        timestamp: Date,
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.timestamp = timestamp
    }

    // MARK: Package

    package let promptTokens: Int?
    package let completionTokens: Int?
    package let totalTokens: Int?
    package let timestamp: Date
}
