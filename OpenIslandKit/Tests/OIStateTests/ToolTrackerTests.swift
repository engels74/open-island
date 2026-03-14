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
