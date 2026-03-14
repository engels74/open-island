package import Foundation

// MARK: - ChatHistoryItem

/// A single item in a session's chat history.
package struct ChatHistoryItem: Sendable, Identifiable {
    // MARK: Lifecycle

    package init(
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

    // MARK: Package

    package let id: String
    package let timestamp: Date
    package let type: ChatItemType
    package let content: String
    package let providerSpecific: JSONValue?
}

// MARK: - ChatItemType

/// The kind of chat history item.
package enum ChatItemType: Sendable, Hashable {
    case user
    case assistant
    case toolCall
    case thinking
    case interrupted
    /// Explicit reasoning output — maps from Codex's `reasoning` item type.
    case reasoning
}
