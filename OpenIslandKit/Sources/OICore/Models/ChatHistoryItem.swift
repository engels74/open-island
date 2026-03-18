public import Foundation

// MARK: - ChatHistoryItem

/// A single item in a session's chat history.
public struct ChatHistoryItem: Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: String,
        timestamp: Date,
        type: ChatItemType,
        content: String,
        providerSpecific: JSONValue? = nil,
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.content = content
        self.providerSpecific = providerSpecific
    }

    // MARK: Public

    public let id: String
    public let timestamp: Date
    public let type: ChatItemType
    public let content: String
    public let providerSpecific: JSONValue?
}

// MARK: - ChatItemType

/// The kind of chat history item.
public enum ChatItemType: Sendable, Hashable {
    case user
    case assistant
    case toolCall
    case thinking
    case interrupted
    /// Explicit reasoning output — maps from Codex's `reasoning` item type.
    case reasoning
}
