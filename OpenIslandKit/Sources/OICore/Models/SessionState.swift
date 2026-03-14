package import Foundation

/// Complete snapshot of a provider session's current state.
package struct SessionState: Sendable, Identifiable {
    // MARK: Lifecycle

    package init(
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

    // MARK: Package

    package let id: String
    package let providerID: ProviderID
    package var phase: SessionPhase
    package let projectName: String
    package let cwd: String
    package let pid: Int32?
    package var chatItems: [ChatHistoryItem]
    package var activeTools: [ToolCallItem]
    package let createdAt: Date
    package var lastActivityAt: Date
    package var tokenUsage: TokenUsageSnapshot?
}
