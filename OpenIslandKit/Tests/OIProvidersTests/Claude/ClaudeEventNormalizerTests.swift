import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - NilEventFixture

struct NilEventFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let json: String

    var testDescription: String {
        self.name
    }
}

// MARK: - ClaudeEventNormalizerNilTests

struct ClaudeEventNormalizerNilTests {
    // MARK: Internal

    @Test(arguments: nilEvents)
    func `Events with no ProviderEvent equivalent return empty array`(fixture: NilEventFixture) throws {
        let event = try JSONDecoder().decode(ClaudeHookEvent.self, from: Data(fixture.json.utf8))
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.isEmpty)
    }

    // MARK: Private

    private static let nilEvents: [NilEventFixture] = [
        NilEventFixture(name: "Setup", json: #"{"session_id":"s1","hook_event_name":"Setup"}"#),
        NilEventFixture(name: "WorktreeCreate", json: #"{"session_id":"s1","hook_event_name":"WorktreeCreate"}"#),
        NilEventFixture(name: "WorktreeRemove", json: #"{"session_id":"s1","hook_event_name":"WorktreeRemove"}"#),
    ]
}

// MARK: - ClaudeEventNormalizerSessionTests

struct ClaudeEventNormalizerSessionTests {
    // MARK: Internal

    @Test
    func `SessionStart normalizes to sessionStarted`() throws {
        let event = try decode("""
        {"session_id":"s1","hook_event_name":"SessionStart","cwd":"/proj","session_type":"startup"}
        """)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .sessionStarted(sid, providerID, cwd, pid) = result.first else {
            Issue.record("Expected .sessionStarted, got \(String(describing: result.first))")
            return
        }
        #expect(sid == "s1")
        #expect(providerID == .claude)
        #expect(cwd == "/proj")
        #expect(pid == nil)
    }

    @Test
    func `SessionStart without cwd defaults to empty string`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"SessionStart"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .sessionStarted(_, _, cwd, _) = result.first else {
            Issue.record("Expected .sessionStarted")
            return
        }
        #expect(cwd.isEmpty)
    }

    @Test
    func `SessionEnd normalizes to sessionEnded`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"SessionEnd"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .sessionEnded(sid) = result.first else {
            Issue.record("Expected .sessionEnded")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `UserPromptSubmit normalizes to userPromptSubmitted`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"UserPromptSubmit"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .userPromptSubmitted(sid) = result.first else {
            Issue.record("Expected .userPromptSubmitted")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `Stop normalizes to waitingForInput`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"Stop"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .waitingForInput(sid) = result.first else {
            Issue.record("Expected .waitingForInput")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `Notification normalizes to notification`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"Notification","message":"heads up"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .notification(sid, message) = result.first else {
            Issue.record("Expected .notification")
            return
        }
        #expect(sid == "s1")
        #expect(message == "heads up")
    }

    @Test
    func `Notification without message defaults to empty string`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"Notification"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .notification(_, message) = result.first else {
            Issue.record("Expected .notification")
            return
        }
        #expect(message.isEmpty)
    }

    @Test
    func `PreCompact normalizes to compacting`() throws {
        let event = try decode(
            #"{"session_id":"s1","hook_event_name":"PreCompact","compaction_reason":"full","message_count":100}"#,
        )
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .compacting(sid) = result.first else {
            Issue.record("Expected .compacting")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `ConfigChange normalizes to configChanged`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"ConfigChange"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .configChanged(sid) = result.first else {
            Issue.record("Expected .configChanged")
            return
        }
        #expect(sid == "s1")
    }

    // MARK: Private

    private func decode(_ json: String) throws -> ClaudeHookEvent {
        try JSONDecoder().decode(ClaudeHookEvent.self, from: Data(json.utf8))
    }
}

// MARK: - ClaudeEventNormalizerToolTests

struct ClaudeEventNormalizerToolTests {
    // MARK: Internal

    @Test
    func `PostToolUse normalizes to toolCompleted with success`() throws {
        let event = try decode("""
        {"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Read","tool_use_id":"tu-2","tool_result":{"content":"data"}}
        """)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .toolCompleted(sid, toolEvent, toolResult) = result.first else {
            Issue.record("Expected .toolCompleted")
            return
        }
        #expect(sid == "s1")
        #expect(toolEvent.name == "Read")
        #expect(toolResult?.isSuccess == true)
        #expect(toolResult?.output?["content"]?.stringValue == "data")
        #expect(toolResult?.errorMessage == nil)
    }

    @Test
    func `PostToolUseFailure normalizes to toolCompleted with failure`() throws {
        let event = try decode("""
        {"session_id":"s1","hook_event_name":"PostToolUseFailure","tool_name":"Write","tool_use_id":"tu-3","error":"Permission denied"}
        """)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .toolCompleted(sid, toolEvent, toolResult) = result.first else {
            Issue.record("Expected .toolCompleted")
            return
        }
        #expect(sid == "s1")
        #expect(toolEvent.name == "Write")
        #expect(toolResult?.isSuccess == false)
        #expect(toolResult?.errorMessage == "Permission denied")
    }

    @Test
    func `PostToolUseFailure with object error uses fallback message`() throws {
        let event = try decode("""
        {"session_id":"s1","hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_use_id":"tu-4","error":{"code":1,"stderr":"not found"}}
        """)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .toolCompleted(_, _, toolResult) = result.first else {
            Issue.record("Expected .toolCompleted")
            return
        }
        #expect(toolResult?.isSuccess == false)
        #expect(toolResult?.errorMessage == "Tool failed")
    }

    @Test
    func `PermissionRequest normalizes to permissionRequested`() throws {
        let event = try decode("""
        {"session_id":"s1","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf /tmp"},"tool_use_id":"tu-5"}
        """)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .permissionRequested(sid, request) = result.first else {
            Issue.record("Expected .permissionRequested")
            return
        }
        #expect(sid == "s1")
        #expect(request.toolName == "Bash")
        #expect(request.id == "tu-5")
        #expect(request.toolInput?["command"]?.stringValue == "rm -rf /tmp")
    }

    @Test
    func `PermissionRequest without tool_name throws`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"PermissionRequest"}"#)
        do {
            _ = try ClaudeEventNormalizer.normalize(event)
            Issue.record("Expected error to be thrown")
        } catch {
            guard case .missingRequiredField("tool_name") = error else {
                Issue.record("Expected .missingRequiredField(\"tool_name\"), got \(error)")
                return
            }
        }
    }

    // MARK: Private

    private func decode(_ json: String) throws -> ClaudeHookEvent {
        try JSONDecoder().decode(ClaudeHookEvent.self, from: Data(json.utf8))
    }
}

// MARK: - ClaudeEventNormalizerSubagentTests

struct ClaudeEventNormalizerSubagentTests {
    // MARK: Internal

    @Test
    func `SubagentStart normalizes to subagentStarted`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"SubagentStart","task_id":"t-1"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .subagentStarted(sid, taskID, parentToolID) = result.first else {
            Issue.record("Expected .subagentStarted")
            return
        }
        #expect(sid == "s1")
        #expect(taskID == "t-1")
        #expect(parentToolID == nil)
    }

    @Test
    func `SubagentStart with parent_context extracts parentToolID`() throws {
        let json = #"{"session_id":"s1","hook_event_name":"SubagentStart","task_id":"t-2","parent_context":{"tool_use_id":"tu-parent"}}"#
        let event = try decode(json)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .subagentStarted(_, _, parentToolID) = result.first else {
            Issue.record("Expected .subagentStarted")
            return
        }
        #expect(parentToolID == "tu-parent")
    }

    @Test
    func `SubagentStart without task_id throws`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"SubagentStart"}"#)
        do {
            _ = try ClaudeEventNormalizer.normalize(event)
            Issue.record("Expected error to be thrown")
        } catch {
            guard case .missingRequiredField("task_id") = error else {
                Issue.record("Expected .missingRequiredField(\"task_id\"), got \(error)")
                return
            }
        }
    }

    @Test
    func `SubagentStop normalizes to subagentStopped`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"SubagentStop","task_id":"t-1"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .subagentStopped(sid, taskID) = result.first else {
            Issue.record("Expected .subagentStopped")
            return
        }
        #expect(sid == "s1")
        #expect(taskID == "t-1")
    }

    @Test
    func `SubagentStop without task_id throws`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"SubagentStop"}"#)
        do {
            _ = try ClaudeEventNormalizer.normalize(event)
            Issue.record("Expected error to be thrown")
        } catch {
            guard case .missingRequiredField("task_id") = error else {
                Issue.record("Expected .missingRequiredField(\"task_id\"), got \(error)")
                return
            }
        }
    }

    @Test
    func `Unknown event type throws unknownEventType`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"SomeNewEvent"}"#)
        do {
            _ = try ClaudeEventNormalizer.normalize(event)
            Issue.record("Expected error to be thrown")
        } catch {
            guard case .unknownEventType("SomeNewEvent") = error else {
                Issue.record("Expected .unknownEventType(\"SomeNewEvent\"), got \(error)")
                return
            }
        }
    }

    // MARK: Private

    private func decode(_ json: String) throws -> ClaudeHookEvent {
        try JSONDecoder().decode(ClaudeHookEvent.self, from: Data(json.utf8))
    }
}

// MARK: - ClaudeEventNormalizerInterruptTests

@Suite(.tags(.claude))
struct ClaudeEventNormalizerInterruptTests {
    // MARK: Internal

    @Test
    func `Stop with interrupted stop_reason emits interruptDetected then waitingForInput`() throws {
        let event = try decode(
            #"{"session_id":"s1","hook_event_name":"Stop","stop_reason":"interrupted"}"#,
        )
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 2)

        guard case let .interruptDetected(sid1) = result[0] else {
            Issue.record("Expected .interruptDetected, got \(result[0])")
            return
        }
        #expect(sid1 == "s1")

        guard case let .waitingForInput(sid2) = result[1] else {
            Issue.record("Expected .waitingForInput, got \(result[1])")
            return
        }
        #expect(sid2 == "s1")
    }

    @Test
    func `Stop without stop_reason does not emit interruptDetected`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"Stop"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case .waitingForInput = result.first else {
            Issue.record("Expected .waitingForInput, got \(String(describing: result.first))")
            return
        }
    }

    @Test
    func `Stop with non-interrupt stop_reason does not emit interruptDetected`() throws {
        let event = try decode(
            #"{"session_id":"s1","hook_event_name":"Stop","stop_reason":"end_turn"}"#,
        )
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case .waitingForInput = result.first else {
            Issue.record("Expected .waitingForInput, got \(String(describing: result.first))")
            return
        }
    }

    // MARK: Private

    private func decode(_ json: String) throws -> ClaudeHookEvent {
        try JSONDecoder().decode(ClaudeHookEvent.self, from: Data(json.utf8))
    }
}

// MARK: - ClaudeEventNormalizerTeamEventTests

@Suite(.tags(.claude))
struct ClaudeEventNormalizerTeamEventTests {
    // MARK: Internal

    @Test
    func `TeammateIdle normalizes to notification`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"TeammateIdle"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .notification(sid, message) = result.first else {
            Issue.record("Expected .notification, got \(String(describing: result.first))")
            return
        }
        #expect(sid == "s1")
        #expect(message == "Teammate idle")
    }

    @Test
    func `TeammateIdle with teammate_session_id includes it in message`() throws {
        let json = #"{"session_id":"s1","hook_event_name":"TeammateIdle","teammate_session_id":"sub-abc"}"#
        let event = try decode(json)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .notification(_, message) = result.first else {
            Issue.record("Expected .notification")
            return
        }
        #expect(message == "Teammate sub-abc idle")
    }

    @Test
    func `TaskCompleted normalizes to subagentStopped`() throws {
        let json = #"{"session_id":"s1","hook_event_name":"TaskCompleted","task_id":"t-1"}"#
        let event = try decode(json)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .subagentStopped(sid, taskID) = result.first else {
            Issue.record("Expected .subagentStopped, got \(String(describing: result.first))")
            return
        }
        #expect(sid == "s1")
        #expect(taskID == "t-1")
    }

    @Test
    func `TaskCompleted without task_id throws`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"TaskCompleted"}"#)
        do {
            _ = try ClaudeEventNormalizer.normalize(event)
            Issue.record("Expected error to be thrown")
        } catch {
            guard case .missingRequiredField("task_id") = error else {
                Issue.record("Expected .missingRequiredField(\"task_id\"), got \(error)")
                return
            }
        }
    }

    // MARK: Private

    private func decode(_ json: String) throws -> ClaudeHookEvent {
        try JSONDecoder().decode(ClaudeHookEvent.self, from: Data(json.utf8))
    }
}
