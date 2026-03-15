import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - EventFixture

struct EventFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let json: String

    var testDescription: String {
        self.name
    }
}

// MARK: - ClaudeHookEventJSON

/// JSON fixtures shared across decoding test suites.
private enum ClaudeHookEventJSON {
    static let sessionStart = """
    {
        "session_id": "abc-123",
        "transcript_path": "/tmp/transcript.json",
        "cwd": "/Users/dev/project",
        "permission_mode": "default",
        "hook_event_name": "SessionStart",
        "session_type": "startup"
    }
    """

    static let sessionEnd = #"{"session_id":"abc-123","hook_event_name":"SessionEnd"}"#

    static let setup = """
    {"session_id":"abc-123","hook_event_name":"Setup","cwd":"/Users/dev/project"}
    """

    static let userPromptSubmit = #"{"session_id":"abc-123","hook_event_name":"UserPromptSubmit"}"#

    static let preToolUse = """
    {
        "session_id": "abc-123",
        "hook_event_name": "PreToolUse",
        "tool_name": "Bash",
        "tool_input": {"command": "ls -la", "description": "List files"},
        "tool_use_id": "tool-001"
    }
    """

    static let postToolUse = """
    {
        "session_id": "abc-123",
        "hook_event_name": "PostToolUse",
        "tool_name": "Read",
        "tool_input": {"file_path": "/tmp/test.txt"},
        "tool_use_id": "tool-002",
        "tool_result": {"content": "file contents here"}
    }
    """

    static let postToolUseFailure = """
    {
        "session_id": "abc-123",
        "hook_event_name": "PostToolUseFailure",
        "tool_name": "Write",
        "tool_input": {"file_path": "/readonly/file.txt"},
        "tool_use_id": "tool-003",
        "error": "Permission denied"
    }
    """

    static let permissionRequest = """
    {
        "session_id": "abc-123",
        "hook_event_name": "PermissionRequest",
        "tool_name": "Bash",
        "tool_input": {"command": "rm -rf /tmp/test"},
        "tool_use_id": "tool-004"
    }
    """

    static let stop = #"{"session_id":"abc-123","hook_event_name":"Stop"}"#
    static let notification = """
    {"session_id":"abc-123","hook_event_name":"Notification","notification_type":"info","message":"Context window is 80% full"}
    """

    static let subagentStart = """
    {"session_id":"abc-123","hook_event_name":"SubagentStart","task_id":"task-789","parent_context":{"goal":"refactor auth module"}}
    """

    static let subagentStop = #"{"session_id":"abc-123","hook_event_name":"SubagentStop","task_id":"task-789"}"#
    static let teammateIdle = #"{"session_id":"abc-123","hook_event_name":"TeammateIdle"}"#
    static let taskCompleted = #"{"session_id":"abc-123","hook_event_name":"TaskCompleted","task_id":"task-789"}"#

    static let preCompact = """
    {"session_id":"abc-123","hook_event_name":"PreCompact","compaction_reason":"context_window_full","message_count":150}
    """

    static let configChange = #"{"session_id":"abc-123","hook_event_name":"ConfigChange"}"#
    static let worktreeCreate = #"{"session_id":"abc-123","hook_event_name":"WorktreeCreate"}"#
    static let worktreeRemove = #"{"session_id":"abc-123","hook_event_name":"WorktreeRemove"}"#

    static let allFixtures: [EventFixture] = [
        EventFixture(name: "Setup", json: setup),
        EventFixture(name: "SessionStart", json: sessionStart),
        EventFixture(name: "SessionEnd", json: sessionEnd),
        EventFixture(name: "UserPromptSubmit", json: userPromptSubmit),
        EventFixture(name: "PreToolUse", json: preToolUse),
        EventFixture(name: "PostToolUse", json: postToolUse),
        EventFixture(name: "PostToolUseFailure", json: postToolUseFailure),
        EventFixture(name: "PermissionRequest", json: permissionRequest),
        EventFixture(name: "Stop", json: stop),
        EventFixture(name: "Notification", json: notification),
        EventFixture(name: "SubagentStart", json: subagentStart),
        EventFixture(name: "SubagentStop", json: subagentStop),
        EventFixture(name: "TeammateIdle", json: teammateIdle),
        EventFixture(name: "TaskCompleted", json: taskCompleted),
        EventFixture(name: "PreCompact", json: preCompact),
        EventFixture(name: "ConfigChange", json: configChange),
        EventFixture(name: "WorktreeCreate", json: worktreeCreate),
        EventFixture(name: "WorktreeRemove", json: worktreeRemove),
    ]
}

// MARK: - ClaudeHookEventDecodingTests

struct ClaudeHookEventDecodingTests {
    @Test(arguments: ClaudeHookEventJSON.allFixtures)
    func `All 18 event types decode successfully`(fixture: EventFixture) throws {
        let data = Data(fixture.json.utf8)
        let event = try JSONDecoder().decode(ClaudeHookEvent.self, from: data)
        #expect(event.hookEventName == fixture.name)
        #expect(event.sessionID == "abc-123")
    }

    @Test
    func `SessionStart decodes all fields`() throws {
        let data = Data(ClaudeHookEventJSON.sessionStart.utf8)
        let event = try JSONDecoder().decode(ClaudeHookEvent.self, from: data)
        #expect(event.sessionID == "abc-123")
        #expect(event.transcriptPath == "/tmp/transcript.json")
        #expect(event.cwd == "/Users/dev/project")
        #expect(event.permissionMode == "default")
        #expect(event.hookEventName == "SessionStart")
        #expect(event.sessionType == "startup")
    }

    @Test
    func `PreToolUse decodes tool fields`() throws {
        let data = Data(ClaudeHookEventJSON.preToolUse.utf8)
        let event = try JSONDecoder().decode(ClaudeHookEvent.self, from: data)
        #expect(event.toolName == "Bash")
        #expect(event.toolUseID == "tool-001")
        #expect(event.toolInput?["command"]?.stringValue == "ls -la")
    }

    @Test
    func `PostToolUse decodes result`() throws {
        let data = Data(ClaudeHookEventJSON.postToolUse.utf8)
        let event = try JSONDecoder().decode(ClaudeHookEvent.self, from: data)
        #expect(event.toolResult?["content"]?.stringValue == "file contents here")
    }

    @Test
    func `PostToolUseFailure decodes error`() throws {
        let data = Data(ClaudeHookEventJSON.postToolUseFailure.utf8)
        let event = try JSONDecoder().decode(ClaudeHookEvent.self, from: data)
        #expect(event.error?.stringValue == "Permission denied")
    }

    @Test
    func `SubagentStart decodes parent context`() throws {
        let data = Data(ClaudeHookEventJSON.subagentStart.utf8)
        let event = try JSONDecoder().decode(ClaudeHookEvent.self, from: data)
        #expect(event.taskID == "task-789")
        #expect(event.parentContext?["goal"]?.stringValue == "refactor auth module")
    }

    @Test
    func `PreCompact decodes compaction fields`() throws {
        let data = Data(ClaudeHookEventJSON.preCompact.utf8)
        let event = try JSONDecoder().decode(ClaudeHookEvent.self, from: data)
        #expect(event.compactionReason == "context_window_full")
        #expect(event.messageCount == 150)
    }

    @Test
    func `Notification decodes message fields`() throws {
        let data = Data(ClaudeHookEventJSON.notification.utf8)
        let event = try JSONDecoder().decode(ClaudeHookEvent.self, from: data)
        #expect(event.notificationType == "info")
        #expect(event.message == "Context window is 80% full")
    }

    @Test
    func `Optional fields default to nil`() throws {
        let data = Data(ClaudeHookEventJSON.stop.utf8)
        let event = try JSONDecoder().decode(ClaudeHookEvent.self, from: data)
        #expect(event.toolName == nil)
        #expect(event.toolInput == nil)
        #expect(event.toolUseID == nil)
        #expect(event.toolResult == nil)
        #expect(event.error == nil)
        #expect(event.sessionType == nil)
        #expect(event.taskID == nil)
        #expect(event.parentContext == nil)
        #expect(event.compactionReason == nil)
        #expect(event.messageCount == nil)
        #expect(event.notificationType == nil)
        #expect(event.message == nil)
        #expect(event.transcriptPath == nil)
        #expect(event.cwd == nil)
        #expect(event.permissionMode == nil)
    }

    @Test
    func `Codable round trip preserves all fields`() throws {
        let data = Data(ClaudeHookEventJSON.preToolUse.utf8)
        let original = try JSONDecoder().decode(ClaudeHookEvent.self, from: data)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClaudeHookEvent.self, from: encoded)
        #expect(decoded.sessionID == original.sessionID)
        #expect(decoded.hookEventName == original.hookEventName)
        #expect(decoded.toolName == original.toolName)
        #expect(decoded.toolUseID == original.toolUseID)
    }
}
