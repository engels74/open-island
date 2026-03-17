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
    /// Returns the subagent context so callers can use its `nestedToolIDs`
    /// and `parentToolID` to build nested tool hierarchies.
    @discardableResult
    package static func processSubagentStopped(
        taskID: String,
        tracker: inout ToolTracker,
    ) -> SubagentContext? {
        guard let index = tracker.activeSubagents.lastIndex(where: { $0.taskID == taskID }) else {
            return nil
        }
        return tracker.activeSubagents.remove(at: index)
    }

    /// Build nested tool items for a completed subagent by finding its parent tool
    /// and attaching its nested tool IDs as children.
    ///
    /// Returns the index of the parent tool in `activeTools` if nesting was applied,
    /// or `nil` if the parent wasn't found.
    @discardableResult
    package static func applyNestedTools(
        subagent: SubagentContext,
        activeTools: inout [ToolCallItem],
    ) -> Int? {
        guard let parentToolID = subagent.parentToolID,
              let parentIndex = activeTools.firstIndex(where: { $0.id == parentToolID })
        else {
            return nil
        }

        // Find nested tool items that belong to this subagent
        let nestedIDs = Set(subagent.nestedToolIDs)
        let nestedItems = activeTools.filter { nestedIDs.contains($0.id) }

        guard !nestedItems.isEmpty else { return nil }

        // Add nested items to the parent tool's nestedTools
        activeTools[parentIndex].nestedTools.append(contentsOf: nestedItems)

        // Remove the nested items from the flat list
        activeTools.removeAll { nestedIDs.contains($0.id) }

        // Re-find parent index after removal (it may have shifted)
        return activeTools.firstIndex { $0.id == parentToolID }
    }
}
