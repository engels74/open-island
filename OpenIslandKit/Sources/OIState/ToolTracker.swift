package import Foundation
package import OICore

// MARK: - ToolTracker

/// Value-type helper — does not replace `SessionState.activeTools`.
/// `ToolEventProcessor` uses it to produce updated `[ToolCallItem]` arrays.
package struct ToolTracker: Sendable {
    // MARK: Lifecycle

    package init() {}

    // MARK: Package

    package var inProgress: [String: ToolInProgress] = [:]

    /// All tool IDs seen during this session (for deduplication).
    package var seenIDs: Set<String> = []

    /// Stack of active subagent contexts (most recent last).
    package var activeSubagents: [SubagentContext] = []
}

// MARK: - ToolInProgress

package struct ToolInProgress: Sendable {
    // MARK: Lifecycle

    package init(
        id: String,
        name: String,
        input: JSONValue? = nil,
        startedAt: Date,
        parentSubagentID: String? = nil,
    ) {
        self.id = id
        self.name = name
        self.input = input
        self.startedAt = startedAt
        self.parentSubagentID = parentSubagentID
    }

    // MARK: Package

    package let id: String
    package let name: String
    package let input: JSONValue?
    package let startedAt: Date
    package var parentSubagentID: String?
}

// MARK: - SubagentContext

package struct SubagentContext: Sendable {
    // MARK: Lifecycle

    package init(taskID: String, parentToolID: String? = nil) {
        self.taskID = taskID
        self.parentToolID = parentToolID
    }

    // MARK: Package

    package let taskID: String
    package let parentToolID: String?
    package var nestedToolIDs: [String] = []
}
