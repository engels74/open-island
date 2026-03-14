package import Foundation
package import OICore

// MARK: - ToolTracker

/// Tracks in-progress tool invocations and subagent context during a session.
///
/// `ToolTracker` is a value-type processing helper that manages tool lifecycle
/// state. It does not replace `SessionState.activeTools` — instead,
/// `ToolEventProcessor` uses it to produce updated `[ToolCallItem]` arrays.
package struct ToolTracker: Sendable {
    // MARK: Lifecycle

    package init() {}

    // MARK: Package

    /// Tools currently executing, keyed by tool ID.
    package var inProgress: [String: ToolInProgress] = [:]

    /// All tool IDs seen during this session (for deduplication).
    package var seenIDs: Set<String> = []

    /// Stack of active subagent contexts (most recent last).
    package var activeSubagents: [SubagentContext] = []
}

// MARK: - ToolInProgress

/// Snapshot of a tool invocation that has started but not yet completed.
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

/// Tracks a subagent (e.g. `Task` tool) and its nested tool invocations.
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
