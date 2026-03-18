public import Foundation

/// Complete snapshot of a provider session's current state.
public struct SessionState: Sendable, Identifiable {
    // MARK: Lifecycle

    public init(
        id: String,
        providerID: ProviderID,
        phase: SessionPhase = .idle,
        projectName: String,
        cwd: String,
        pid: Int32? = nil,
        chatItems: [ChatHistoryItem] = [],
        activeTools: [ToolCallItem] = [],
        createdAt: Date,
        lastActivityAt: Date,
        tokenUsage: TokenUsageSnapshot? = nil,
    ) {
        self.id = id
        self.providerID = providerID
        self.phase = phase
        self.projectName = projectName
        self.cwd = cwd
        self.pid = pid
        self.chatItems = chatItems
        self.activeTools = activeTools
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.tokenUsage = tokenUsage
    }

    // MARK: Public

    public let id: String
    public let providerID: ProviderID
    public var phase: SessionPhase
    public let projectName: String
    public let cwd: String
    public let pid: Int32?
    public var chatItems: [ChatHistoryItem]
    public var activeTools: [ToolCallItem]
    public let createdAt: Date
    public var lastActivityAt: Date
    public var tokenUsage: TokenUsageSnapshot?
}
