package import Foundation
package import OICore

// MARK: - ToolEventProcessor

package enum ToolEventProcessor {
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

    package static func processSubagentStarted(
        taskID: String,
        parentToolID: String?,
        tracker: inout ToolTracker,
    ) {
        let context = SubagentContext(taskID: taskID, parentToolID: parentToolID)
        tracker.activeSubagents.append(context)
    }

    /// Searches from the top of the stack (LIFO) since subagents can nest.
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

        let nestedIDs = Set(subagent.nestedToolIDs)
        let nestedItems = activeTools.filter { nestedIDs.contains($0.id) }

        guard !nestedItems.isEmpty else { return nil }

        activeTools[parentIndex].nestedTools.append(contentsOf: nestedItems)

        activeTools.removeAll { nestedIDs.contains($0.id) }

        // Re-find parent index after removal (it may have shifted)
        return activeTools.firstIndex { $0.id == parentToolID }
    }
}
