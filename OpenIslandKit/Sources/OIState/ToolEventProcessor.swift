package import Foundation
package import OICore

// MARK: - ToolEventProcessor

/// Static methods that process tool and subagent events, updating a
/// `ToolTracker` and returning `ToolCallItem` values for `SessionState.activeTools`.
package enum ToolEventProcessor {
    /// Process a tool-started event. Returns a new `ToolCallItem` with `.running` status.
    ///
    /// Adds the tool to `tracker.inProgress` and `tracker.seenIDs`.
    /// If a subagent is active, links the tool to that subagent context.
    package static func processToolStarted(
        _ event: ToolEvent,
        tracker: inout ToolTracker,
    ) -> ToolCallItem {
        var toolInProgress = ToolInProgress(
            id: event.id,
            name: event.name,
            input: event.input,
            startedAt: event.startedAt,
        )

        // If there's an active subagent, attribute this tool to it.
        if var subagent = tracker.activeSubagents.last {
            toolInProgress.parentSubagentID = subagent.taskID
            subagent.nestedToolIDs.append(event.id)
            tracker.activeSubagents[tracker.activeSubagents.count - 1] = subagent
        }

        tracker.inProgress[event.id] = toolInProgress
        tracker.seenIDs.insert(event.id)

        return ToolCallItem(
            id: event.id,
            name: event.name,
            input: event.input,
            status: .running,
        )
    }

    /// Process a tool-completed event. Returns an updated `ToolCallItem` with
    /// final status and duration, or `nil` if the tool was not tracked.
    package static func processToolCompleted(
        _ event: ToolEvent,
        result: ToolResult?,
        tracker: inout ToolTracker,
    ) -> ToolCallItem? {
        guard let started = tracker.inProgress.removeValue(forKey: event.id) else {
            return nil
        }

        let status: ToolStatus = if let result {
            result.isSuccess ? .success : .error
        } else {
            .interrupted
        }

        let duration = result?.duration ?? event.startedAt.distance(to: Date.now)

        return ToolCallItem(
            id: event.id,
            name: event.name,
            input: event.input,
            status: status,
            result: result?.output,
            providerSpecific: started.input != event.input ? event.input : nil,
        )
    }

    /// Push a new subagent context onto the tracker's active subagent stack.
    package static func processSubagentStarted(
        taskID: String,
        parentToolID: String?,
        tracker: inout ToolTracker,
    ) {
        let context = SubagentContext(taskID: taskID, parentToolID: parentToolID)
        tracker.activeSubagents.append(context)
    }

    /// Pop the matching subagent from the tracker's active subagent stack.
    ///
    /// Searches from the top of the stack and removes the first match.
    package static func processSubagentStopped(
        taskID: String,
        tracker: inout ToolTracker,
    ) {
        if let index = tracker.activeSubagents.lastIndex(where: { $0.taskID == taskID }) {
            tracker.activeSubagents.remove(at: index)
        }
    }
}
