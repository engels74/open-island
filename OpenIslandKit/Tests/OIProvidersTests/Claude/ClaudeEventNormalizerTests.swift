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
    func `Events with no ProviderEvent equivalent return nil`(fixture: NilEventFixture) throws {
        let event = try JSONDecoder().decode(ClaudeHookEvent.self, from: Data(fixture.json.utf8))
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result == nil)
    }

    // MARK: Private

    private static let nilEvents: [NilEventFixture] = [
        NilEventFixture(name: "Setup", json: #"{"session_id":"s1","hook_event_name":"Setup"}"#),
        NilEventFixture(name: "TeammateIdle", json: #"{"session_id":"s1","hook_event_name":"TeammateIdle"}"#),
        NilEventFixture(name: "TaskCompleted", json: #"{"session_id":"s1","hook_event_name":"TaskCompleted"}"#),
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
        guard case let .sessionStarted(sid, cwd, pid) = result else {
            Issue.record("Expected .sessionStarted, got \(String(describing: result))")
            return
        }
        #expect(sid == "s1")
        #expect(cwd == "/proj")
        #expect(pid == nil)
    }

    @Test
    func `SessionStart without cwd defaults to empty string`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"SessionStart"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        guard case let .sessionStarted(_, cwd, _) = result else {
            Issue.record("Expected .sessionStarted")
            return
        }
        #expect(cwd.isEmpty)
    }

    @Test
    func `SessionEnd normalizes to sessionEnded`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"SessionEnd"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        guard case let .sessionEnded(sid) = result else {
            Issue.record("Expected .sessionEnded")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `UserPromptSubmit normalizes to userPromptSubmitted`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"UserPromptSubmit"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        guard case let .userPromptSubmitted(sid) = result else {
            Issue.record("Expected .userPromptSubmitted")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `Stop normalizes to waitingForInput`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"Stop"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        guard case let .waitingForInput(sid) = result else {
            Issue.record("Expected .waitingForInput")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `Notification normalizes to notification`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"Notification","message":"heads up"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        guard case let .notification(sid, message) = result else {
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
        guard case let .notification(_, message) = result else {
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
        guard case let .compacting(sid) = result else {
            Issue.record("Expected .compacting")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `ConfigChange normalizes to configChanged`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"ConfigChange"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        guard case let .configChanged(sid) = result else {
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
        guard case let .toolCompleted(sid, toolEvent, toolResult) = result else {
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
        guard case let .toolCompleted(sid, toolEvent, toolResult) = result else {
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
        guard case let .toolCompleted(_, _, toolResult) = result else {
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
        guard case let .permissionRequested(sid, request) = result else {
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
        guard case let .subagentStarted(sid, taskID, parentToolID) = result else {
            Issue.record("Expected .subagentStarted")
            return
        }
        #expect(sid == "s1")
        #expect(taskID == "t-1")
        #expect(parentToolID == nil)
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
        guard case let .subagentStopped(sid, taskID) = result else {
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
