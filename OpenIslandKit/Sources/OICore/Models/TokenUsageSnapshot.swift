public import Foundation

/// A point-in-time snapshot of token usage for a session.
public struct TokenUsageSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    public init(
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

    // MARK: Public

    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?
    public let timestamp: Date
}
