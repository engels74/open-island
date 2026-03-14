// MARK: - ToolCallItem

/// A tool invocation within a provider session, tracked for UI display.
package struct ToolCallItem: Sendable, Identifiable {
    // MARK: Lifecycle

    package init(
        id: String,
        name: String,
        input: JSONValue? = nil,
        status: ToolStatus = .running,
        result: JSONValue? = nil,
        nestedTools: [Self] = [],
        providerSpecific: JSONValue? = nil,
    ) {
        self.id = id
        self.name = name
        self.input = input
        self.status = status
        self.result = result
        self.nestedTools = nestedTools
        self.providerSpecific = providerSpecific
    }

    // MARK: Package

    package let id: String
    package let name: String
    package let input: JSONValue?
    package var status: ToolStatus
    package var result: JSONValue?
    package var nestedTools: [Self]
    package let providerSpecific: JSONValue?
}

// MARK: - ToolStatus

/// Execution status of a tool call.
package enum ToolStatus: Sendable, Hashable, BitwiseCopyable {
    case running
    case success
    case error
    case interrupted
}
