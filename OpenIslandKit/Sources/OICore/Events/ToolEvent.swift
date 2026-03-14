package import Foundation

// MARK: - ToolEvent

/// Describes a tool invocation within a provider session.
package struct ToolEvent: Sendable {
    // MARK: Lifecycle

    package init(id: String, name: String, input: JSONValue? = nil, startedAt: Date) {
        self.id = id
        self.name = name
        self.input = input
        self.startedAt = startedAt
    }

    // MARK: Package

    package let id: String
    package let name: String
    package let input: JSONValue?
    package let startedAt: Date
}

// MARK: - ToolResult

/// The result of a completed tool invocation.
package struct ToolResult: Sendable {
    // MARK: Lifecycle

    package init(
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

    // MARK: Package

    package let output: JSONValue?
    package let isSuccess: Bool
    package let duration: TimeInterval?
    package let errorMessage: String?
}
