import Foundation
@testable import OICore
@testable import OIState
import Testing

// MARK: - ToolEventProcessorTests

struct ToolEventProcessorTests {
    // MARK: Internal

    // MARK: - processToolStarted

    @Test
    func `processToolStarted creates a running ToolCallItem`() {
        var tracker = ToolTracker()
        let event = self.makeToolEvent()

        let item = ToolEventProcessor.processToolStarted(event, tracker: &tracker)

        #expect(item.id == "tool1")
        #expect(item.name == "Bash")
        #expect(item.status == .running)
        #expect(tracker.inProgress["tool1"] != nil)
        #expect(tracker.seenIDs.contains("tool1"))
    }

    @Test
    func `processToolStarted records tool in seenIDs`() {
        var tracker = ToolTracker()
        let event = self.makeToolEvent(id: "abc")

        _ = ToolEventProcessor.processToolStarted(event, tracker: &tracker)

        #expect(tracker.seenIDs.contains("abc"))
    }

    // MARK: - processToolCompleted

    @Test
    func `processToolCompleted returns .success for successful result`() {
        var tracker = ToolTracker()
        let event = self.makeToolEvent(id: "t1")
        _ = ToolEventProcessor.processToolStarted(event, tracker: &tracker)

        let result = ToolResult(isSuccess: true, duration: 0.5)
        let item = ToolEventProcessor.processToolCompleted(event, result: result, tracker: &tracker)

        #expect(item?.status == .success)
        #expect(tracker.inProgress["t1"] == nil)
    }

    @Test
    func `processToolCompleted returns .error for failed result`() {
        var tracker = ToolTracker()
        let event = self.makeToolEvent(id: "t2")
        _ = ToolEventProcessor.processToolStarted(event, tracker: &tracker)

        let result = ToolResult(isSuccess: false, errorMessage: "command failed")
        let item = ToolEventProcessor.processToolCompleted(event, result: result, tracker: &tracker)

        #expect(item?.status == .error)
    }

    @Test
    func `processToolCompleted returns .interrupted when result is nil`() {
        var tracker = ToolTracker()
        let event = self.makeToolEvent(id: "t3")
        _ = ToolEventProcessor.processToolStarted(event, tracker: &tracker)

        let item = ToolEventProcessor.processToolCompleted(event, result: nil, tracker: &tracker)

        #expect(item?.status == .interrupted)
    }

    @Test
    func `processToolCompleted returns nil for untracked tool`() {
        var tracker = ToolTracker()
        let event = self.makeToolEvent(id: "unknown")

        let item = ToolEventProcessor.processToolCompleted(event, result: nil, tracker: &tracker)

        #expect(item == nil)
    }

    // MARK: - Subagent Context

    @Test
    func `processSubagentStarted pushes context onto stack`() {
        var tracker = ToolTracker()

        ToolEventProcessor.processSubagentStarted(
            taskID: "task1",
            parentToolID: "parent1",
            tracker: &tracker,
        )

        #expect(tracker.activeSubagents.count == 1)
        #expect(tracker.activeSubagents.first?.taskID == "task1")
        #expect(tracker.activeSubagents.first?.parentToolID == "parent1")
    }

    @Test
    func `processSubagentStopped pops matching context from stack`() {
        var tracker = ToolTracker()

        ToolEventProcessor.processSubagentStarted(taskID: "task1", parentToolID: nil, tracker: &tracker)
        ToolEventProcessor.processSubagentStarted(taskID: "task2", parentToolID: nil, tracker: &tracker)
        #expect(tracker.activeSubagents.count == 2)

        ToolEventProcessor.processSubagentStopped(taskID: "task2", tracker: &tracker)
        #expect(tracker.activeSubagents.count == 1)
        #expect(tracker.activeSubagents.first?.taskID == "task1")
    }

    @Test
    func `nested tools are attributed to parent subagent`() {
        var tracker = ToolTracker()

        ToolEventProcessor.processSubagentStarted(taskID: "agent1", parentToolID: nil, tracker: &tracker)

        let event = self.makeToolEvent(id: "nested-tool")
        let item = ToolEventProcessor.processToolStarted(event, tracker: &tracker)

        #expect(item.status == .running)
        #expect(tracker.inProgress["nested-tool"]?.parentSubagentID == "agent1")
        #expect(tracker.activeSubagents.last?.nestedToolIDs.contains("nested-tool") == true)
    }

    @Test
    func `tool without active subagent has nil parentSubagentID`() {
        var tracker = ToolTracker()
        let event = self.makeToolEvent(id: "solo-tool")

        _ = ToolEventProcessor.processToolStarted(event, tracker: &tracker)

        #expect(tracker.inProgress["solo-tool"]?.parentSubagentID == nil)
    }

    @Test
    func `nested subagent stacking and unstacking`() {
        var tracker = ToolTracker()

        ToolEventProcessor.processSubagentStarted(taskID: "outer", parentToolID: nil, tracker: &tracker)
        ToolEventProcessor.processSubagentStarted(taskID: "inner", parentToolID: "outer-tool", tracker: &tracker)
        #expect(tracker.activeSubagents.count == 2)

        // Tool started while inner subagent is active
        let event = self.makeToolEvent(id: "deep-tool")
        _ = ToolEventProcessor.processToolStarted(event, tracker: &tracker)
        #expect(tracker.inProgress["deep-tool"]?.parentSubagentID == "inner")

        // Stop inner subagent
        ToolEventProcessor.processSubagentStopped(taskID: "inner", tracker: &tracker)
        #expect(tracker.activeSubagents.count == 1)

        // Now a new tool should be attributed to outer
        let event2 = self.makeToolEvent(id: "outer-tool-2")
        _ = ToolEventProcessor.processToolStarted(event2, tracker: &tracker)
        #expect(tracker.inProgress["outer-tool-2"]?.parentSubagentID == "outer")
    }

    // MARK: Private

    // MARK: - Helpers

    private func makeToolEvent(
        id: String = "tool1",
        name: String = "Bash",
        input: JSONValue? = nil,
    ) -> ToolEvent {
        ToolEvent(id: id, name: name, input: input, startedAt: Date())
    }
}

// MARK: - ToolEventProcessorNestedToolTests

struct ToolEventProcessorNestedToolTests {
    @Test
    func `processSubagentStopped returns the removed subagent context`() {
        var tracker = ToolTracker()
        ToolEventProcessor.processSubagentStarted(taskID: "task1", parentToolID: "tu-parent", tracker: &tracker)

        let event = ToolEvent(id: "nested-1", name: "Read", startedAt: Date())
        _ = ToolEventProcessor.processToolStarted(event, tracker: &tracker)

        let context = ToolEventProcessor.processSubagentStopped(taskID: "task1", tracker: &tracker)

        #expect(context != nil)
        #expect(context?.taskID == "task1")
        #expect(context?.parentToolID == "tu-parent")
        #expect(context?.nestedToolIDs == ["nested-1"])
    }

    @Test
    func `processSubagentStopped returns nil for unknown taskID`() {
        var tracker = ToolTracker()
        let context = ToolEventProcessor.processSubagentStopped(taskID: "nonexistent", tracker: &tracker)
        #expect(context == nil)
    }

    @Test
    func `applyNestedTools moves nested items under parent tool`() {
        var activeTools: [ToolCallItem] = [
            ToolCallItem(id: "tu-parent", name: "Task", status: .running),
            ToolCallItem(id: "nested-1", name: "Read", status: .success),
            ToolCallItem(id: "nested-2", name: "Bash", status: .success),
            ToolCallItem(id: "unrelated", name: "Edit", status: .running),
        ]

        var subagent = SubagentContext(taskID: "task1", parentToolID: "tu-parent")
        subagent.nestedToolIDs = ["nested-1", "nested-2"]

        let parentIndex = ToolEventProcessor.applyNestedTools(subagent: subagent, activeTools: &activeTools)

        #expect(parentIndex != nil)
        // The flat list should no longer contain the nested items
        #expect(activeTools.count == 2) // tu-parent and unrelated
        #expect(activeTools.contains { $0.id == "unrelated" })

        // The parent should have nested tools
        let parent = activeTools.first { $0.id == "tu-parent" }
        #expect(parent?.nestedTools.count == 2)
        #expect(parent?.nestedTools.contains { $0.id == "nested-1" } == true)
        #expect(parent?.nestedTools.contains { $0.id == "nested-2" } == true)
    }

    @Test
    func `applyNestedTools returns nil when parentToolID is nil`() {
        var activeTools: [ToolCallItem] = [
            ToolCallItem(id: "tool1", name: "Bash", status: .success),
        ]

        let subagent = SubagentContext(taskID: "task1", parentToolID: nil)

        let result = ToolEventProcessor.applyNestedTools(subagent: subagent, activeTools: &activeTools)
        #expect(result == nil)
        #expect(activeTools.count == 1) // unchanged
    }

    @Test
    func `applyNestedTools returns nil when parent tool not found`() {
        var activeTools: [ToolCallItem] = [
            ToolCallItem(id: "tool1", name: "Bash", status: .success),
        ]

        var subagent = SubagentContext(taskID: "task1", parentToolID: "missing-parent")
        subagent.nestedToolIDs = ["tool1"]

        let result = ToolEventProcessor.applyNestedTools(subagent: subagent, activeTools: &activeTools)
        #expect(result == nil)
        #expect(activeTools.count == 1) // unchanged
    }

    @Test
    func `full subagent lifecycle: start → tools attributed → stop → nested`() throws {
        var tracker = ToolTracker()
        var activeTools: [ToolCallItem] = []

        // Parent tool starts
        let parentEvent = ToolEvent(id: "tu-task", name: "Task", startedAt: Date())
        let parentItem = ToolEventProcessor.processToolStarted(parentEvent, tracker: &tracker)
        activeTools.append(parentItem)

        // Subagent starts with the parent tool
        ToolEventProcessor.processSubagentStarted(taskID: "sub-1", parentToolID: "tu-task", tracker: &tracker)

        // Nested tools execute within the subagent
        let nestedEvent1 = ToolEvent(id: "n1", name: "Read", startedAt: Date())
        let nestedItem1 = ToolEventProcessor.processToolStarted(nestedEvent1, tracker: &tracker)
        activeTools.append(nestedItem1)
        #expect(tracker.inProgress["n1"]?.parentSubagentID == "sub-1")

        let nestedEvent2 = ToolEvent(id: "n2", name: "Bash", startedAt: Date())
        let nestedItem2 = ToolEventProcessor.processToolStarted(nestedEvent2, tracker: &tracker)
        activeTools.append(nestedItem2)

        // Nested tools complete
        let result = ToolResult(isSuccess: true)
        if let completed1 = ToolEventProcessor.processToolCompleted(nestedEvent1, result: result, tracker: &tracker) {
            if let idx = activeTools.firstIndex(where: { $0.id == completed1.id }) {
                activeTools[idx] = completed1
            }
        }
        if let completed2 = ToolEventProcessor.processToolCompleted(nestedEvent2, result: result, tracker: &tracker) {
            if let idx = activeTools.firstIndex(where: { $0.id == completed2.id }) {
                activeTools[idx] = completed2
            }
        }

        // Subagent stops
        let subagent = ToolEventProcessor.processSubagentStopped(taskID: "sub-1", tracker: &tracker)
        #expect(subagent != nil)

        // Apply nesting
        try ToolEventProcessor.applyNestedTools(subagent: #require(subagent), activeTools: &activeTools)

        // Verify nested structure
        #expect(activeTools.count == 1) // only the parent remains at top level
        let parent = try #require(activeTools.first)
        #expect(parent.id == "tu-task")
        #expect(parent.nestedTools.count == 2)
    }
}

// MARK: - SubagentContextTests

struct SubagentContextTests {
    @Test
    func `init with defaults and mutated nestedToolIDs`() {
        var context = SubagentContext(taskID: "t1", parentToolID: "p1")
        context.nestedToolIDs = ["n1", "n2"]
        #expect(context.taskID == "t1")
        #expect(context.parentToolID == "p1")
        #expect(context.nestedToolIDs == ["n1", "n2"])
    }

    @Test
    func `init with nil parentToolID`() {
        let context = SubagentContext(taskID: "t1")
        #expect(context.taskID == "t1")
        #expect(context.parentToolID == nil)
        #expect(context.nestedToolIDs.isEmpty)
    }
}

// MARK: - ToolTrackerTests

struct ToolTrackerTests {
    @Test
    func `init creates empty tracker`() {
        let tracker = ToolTracker()
        #expect(tracker.inProgress.isEmpty)
        #expect(tracker.seenIDs.isEmpty)
        #expect(tracker.activeSubagents.isEmpty)
    }
}
