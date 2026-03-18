// MARK: - ToolCallItem

/// A tool invocation within a provider session, tracked for UI display.
public struct ToolCallItem: Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
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

    // MARK: Public

    public let id: String
    public let name: String
    public let input: JSONValue?
    public var status: ToolStatus
    public var result: JSONValue?
    public var nestedTools: [Self]
    public let providerSpecific: JSONValue?
}

// MARK: - ToolStatus

/// Execution status of a tool call.
public enum ToolStatus: Sendable, Hashable, BitwiseCopyable {
    case running
    case success
    case error
    case interrupted
}
