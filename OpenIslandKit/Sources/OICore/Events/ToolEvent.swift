public import Foundation

// MARK: - ToolEvent

/// Describes a tool invocation within a provider session.
public struct ToolEvent: Sendable {
    // MARK: Lifecycle

    public init(id: String, name: String, input: JSONValue? = nil, startedAt: Date) {
        self.id = id
        self.name = name
        self.input = input
        self.startedAt = startedAt
    }

    // MARK: Public

    public let id: String
    public let name: String
    public let input: JSONValue?
    public let startedAt: Date
}

// MARK: - ToolResult

/// The result of a completed tool invocation.
public struct ToolResult: Sendable {
    // MARK: Lifecycle

    public init(
        output: JSONValue? = nil,
        isSuccess: Bool,
        duration: TimeInterval? = nil,
        errorMessage: String? = nil,
    ) {
        self.output = output
        self.isSuccess = isSuccess
        self.duration = duration
        self.errorMessage = errorMessage
    }

    // MARK: Public

    public let output: JSONValue?
    public let isSuccess: Bool
    public let duration: TimeInterval?
    public let errorMessage: String?
}
