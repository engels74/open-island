import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - ClaudeEventNormalizerPreToolUseTests

@Suite(.tags(.claude))
struct ClaudeEventNormalizerPreToolUseTests {
    // MARK: Internal

    @Test
    func `PreToolUse normalizes to permissionRequested`() throws {
        let json = """
        {"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"tu-pre","tool_input":{"command":"ls"}}
        """
        let event = try decode(json)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .permissionRequested(sid, request) = result.first else {
            Issue.record("Expected .permissionRequested, got \(String(describing: result.first))")
            return
        }
        #expect(sid == "s1")
        #expect(request.toolName == "Bash")
        #expect(request.id == "tu-pre")
        #expect(request.toolInput?["command"]?.stringValue == "ls")
    }

    @Test
    func `PreToolUse without tool_use_id throws`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash"}"#)
        do {
            _ = try ClaudeEventNormalizer.normalize(event)
            Issue.record("Expected error to be thrown")
        } catch {
            guard case .missingRequiredField("tool_use_id") = error else {
                Issue.record("Expected .missingRequiredField(\"tool_use_id\"), got \(error)")
                return
            }
        }
    }

    @Test
    func `PreToolUse without tool_name throws`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"PreToolUse"}"#)
        do {
            _ = try ClaudeEventNormalizer.normalize(event)
            Issue.record("Expected error to be thrown")
        } catch {
            guard case .missingRequiredField("tool_use_id") = error else {
                Issue.record("Expected .missingRequiredField(\"tool_use_id\"), got \(error)")
                return
            }
        }
    }

    // MARK: Private

    private func decode(_ json: String) throws -> ClaudeHookEvent {
        try JSONDecoder().decode(ClaudeHookEvent.self, from: Data(json.utf8))
    }
}

// MARK: - ClaudeEventNormalizerNewEventTests

@Suite(.tags(.claude))
struct ClaudeEventNormalizerNewEventTests {
    // MARK: Internal

    @Test
    func `StopFailure normalizes to notification`() throws {
        let event = try decode(
            #"{"session_id":"s1","hook_event_name":"StopFailure","stop_reason":"api_error"}"#,
        )
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .notification(sid, message) = result.first else {
            Issue.record("Expected .notification, got \(String(describing: result.first))")
            return
        }
        #expect(sid == "s1")
        #expect(message.contains("api_error"))
    }

    @Test
    func `StopFailure without reason uses fallback message`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"StopFailure"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .notification(_, message) = result.first else {
            Issue.record("Expected .notification")
            return
        }
        #expect(message.contains("unknown error"))
    }

    @Test
    func `PostCompact normalizes to notification`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"PostCompact"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .notification(sid, message) = result.first else {
            Issue.record("Expected .notification, got \(String(describing: result.first))")
            return
        }
        #expect(sid == "s1")
        #expect(message == "Context compacted")
    }

    @Test
    func `InstructionsLoaded normalizes to notification with file path`() throws {
        let json = #"{"session_id":"s1","hook_event_name":"InstructionsLoaded","file_path":"/proj/CLAUDE.md"}"#
        let event = try decode(json)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .notification(sid, message) = result.first else {
            Issue.record("Expected .notification, got \(String(describing: result.first))")
            return
        }
        #expect(sid == "s1")
        #expect(message.contains("CLAUDE.md"))
    }

    @Test
    func `InstructionsLoaded without file_path uses fallback`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"InstructionsLoaded"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .notification(_, message) = result.first else {
            Issue.record("Expected .notification")
            return
        }
        #expect(message.contains("instructions"))
    }

    @Test
    func `Elicitation normalizes to notification`() throws {
        let json = #"{"session_id":"s1","hook_event_name":"Elicitation","message":"Choose an option"}"#
        let event = try decode(json)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .notification(sid, message) = result.first else {
            Issue.record("Expected .notification, got \(String(describing: result.first))")
            return
        }
        #expect(sid == "s1")
        #expect(message.contains("Choose an option"))
    }

    @Test
    func `Elicitation without message uses fallback`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"Elicitation"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .notification(_, message) = result.first else {
            Issue.record("Expected .notification")
            return
        }
        #expect(message.contains("user input requested"))
    }

    @Test
    func `ElicitationResult normalizes to notification`() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"ElicitationResult"}"#)
        let result = try ClaudeEventNormalizer.normalize(event)
        #expect(result.count == 1)
        guard case let .notification(sid, message) = result.first else {
            Issue.record("Expected .notification, got \(String(describing: result.first))")
            return
        }
        #expect(sid == "s1")
        #expect(message == "Elicitation completed")
    }

    // MARK: Private

    private func decode(_ json: String) throws -> ClaudeHookEvent {
        try JSONDecoder().decode(ClaudeHookEvent.self, from: Data(json.utf8))
    }
}
