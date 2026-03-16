import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - GeminiEventNormalizerSessionTests

@Suite(.tags(.gemini))
struct GeminiEventNormalizerSessionTests {
    @Test
    func `SessionStart normalizes to sessionStarted`() throws {
        let data = Data(#"{"hook_event_name":"SessionStart","session_id":"s1","cwd":"/proj"}"#.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        #expect(events.count == 1)
        guard case let .sessionStarted(sid, cwd, pid) = events.first else {
            Issue.record("Expected .sessionStarted, got \(String(describing: events.first))")
            return
        }
        #expect(sid == "s1")
        #expect(cwd == "/proj")
        #expect(pid == nil)
    }

    @Test
    func `SessionStart without cwd defaults to empty string`() throws {
        let data = Data(#"{"hook_event_name":"SessionStart","session_id":"s1"}"#.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        guard case let .sessionStarted(_, cwd, _) = events.first else {
            Issue.record("Expected .sessionStarted")
            return
        }
        #expect(cwd.isEmpty)
    }

    @Test
    func `SessionEnd normalizes to sessionEnded`() throws {
        let data = Data(#"{"hook_event_name":"SessionEnd","session_id":"s1"}"#.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        guard case let .sessionEnded(sid) = events.first else {
            Issue.record("Expected .sessionEnded")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `BeforeAgent normalizes to userPromptSubmitted and processingStarted`() throws {
        let data = Data(#"{"hook_event_name":"BeforeAgent","session_id":"s1"}"#.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        #expect(events.count == 2)
        guard case let .userPromptSubmitted(sid1) = events[0] else {
            Issue.record("Expected .userPromptSubmitted, got \(events[0])")
            return
        }
        #expect(sid1 == "s1")
        guard case let .processingStarted(sid2) = events[1] else {
            Issue.record("Expected .processingStarted, got \(events[1])")
            return
        }
        #expect(sid2 == "s1")
    }

    @Test
    func `AfterAgent normalizes to waitingForInput`() throws {
        let data = Data(#"{"hook_event_name":"AfterAgent","session_id":"s1"}"#.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        guard case let .waitingForInput(sid) = events.first else {
            Issue.record("Expected .waitingForInput")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `BeforeModel normalizes to processingStarted`() throws {
        let data = Data(#"{"hook_event_name":"BeforeModel","session_id":"s1"}"#.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        guard case let .processingStarted(sid) = events.first else {
            Issue.record("Expected .processingStarted")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `PreCompress normalizes to compacting`() throws {
        let data = Data(#"{"hook_event_name":"PreCompress","session_id":"s1"}"#.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        guard case let .compacting(sid) = events.first else {
            Issue.record("Expected .compacting")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `BeforeToolSelection returns empty array`() throws {
        let data = Data(#"{"hook_event_name":"BeforeToolSelection","session_id":"s1"}"#.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        #expect(events.isEmpty)
    }
}

// MARK: - GeminiEventNormalizerToolTests

@Suite(.tags(.gemini))
struct GeminiEventNormalizerToolTests {
    @Test
    func `BeforeTool normalizes to toolStarted`() throws {
        let data = Data(#"{"hook_event_name":"BeforeTool","session_id":"s1","tool_name":"Bash","timestamp":"t1"}"#.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        #expect(events.count == 1)
        guard case let .toolStarted(sid, toolEvent) = events.first else {
            Issue.record("Expected .toolStarted")
            return
        }
        #expect(sid == "s1")
        #expect(toolEvent.name == "Bash")
    }

    @Test
    func `BeforeTool without tool_name throws missingRequiredField`() {
        let data = Data(#"{"hook_event_name":"BeforeTool","session_id":"s1"}"#.utf8)
        #expect(throws: EventNormalizationError.self) {
            _ = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        }
    }

    @Test
    func `AfterTool normalizes to toolCompleted`() throws {
        let json = #"{"hook_event_name":"AfterTool","session_id":"s1","# +
            #""tool_name":"Read","timestamp":"t2","tool_response":{"llmContent":"file data"}}"#
        let data = Data(json.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        guard case let .toolCompleted(sid, toolEvent, toolResult) = events.first else {
            Issue.record("Expected .toolCompleted")
            return
        }
        #expect(sid == "s1")
        #expect(toolEvent.name == "Read")
        #expect(toolResult?.isSuccess == true)
    }

    @Test
    func `AfterTool with error is failure`() throws {
        let json = #"{"hook_event_name":"AfterTool","session_id":"s1","# +
            #""tool_name":"Bash","timestamp":"t3","tool_response":{"error":"Permission denied"}}"#
        let data = Data(json.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        guard case let .toolCompleted(_, _, toolResult) = events.first else {
            Issue.record("Expected .toolCompleted")
            return
        }
        #expect(toolResult?.isSuccess == false)
        #expect(toolResult?.errorMessage == "Permission denied")
    }
}

// MARK: - GeminiEventNormalizerAfterModelTests

@Suite(.tags(.gemini))
struct GeminiEventNormalizerAfterModelTests {
    @Test
    func `AfterModel with nil lastAfterModelTime emits event and returns updatedThrottleTime`() throws {
        let data = Data(#"{"hook_event_name":"AfterModel","session_id":"s1","text":"Hello"}"#.utf8)
        let (events, updatedTime) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        #expect(!events.isEmpty)
        // Should have modelResponse
        let hasModelResponse = events.contains { event in
            if case .modelResponse = event { return true }
            return false
        }
        #expect(hasModelResponse)
        #expect(updatedTime != nil)
    }

    @Test
    func `AfterModel with recent lastAfterModelTime skips modelResponse due to throttle`() throws {
        let data = Data(#"{"hook_event_name":"AfterModel","session_id":"s1","text":"Hello"}"#.utf8)
        let recentTime = Date() // Just now
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: recentTime)
        // modelResponse should be skipped due to throttle
        let hasModelResponse = events.contains { event in
            if case .modelResponse = event { return true }
            return false
        }
        #expect(!hasModelResponse)
    }

    @Test
    func `AfterModel with distant past lastAfterModelTime emits event`() throws {
        let data = Data(#"{"hook_event_name":"AfterModel","session_id":"s1","text":"Hello"}"#.utf8)
        let (events, updatedTime) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: Date.distantPast)
        let hasModelResponse = events.contains { event in
            if case .modelResponse = event { return true }
            return false
        }
        #expect(hasModelResponse)
        #expect(updatedTime != nil)
        // updatedTime should be more recent than distantPast
        if let updated = updatedTime {
            #expect(updated > Date.distantPast)
        }
    }

    @Test
    func `AfterModel with usageMetadata emits tokenUsage`() throws {
        let json = #"{"hook_event_name":"AfterModel","session_id":"s1","# +
            #""usageMetadata":{"promptTokenCount":100,"candidatesTokenCount":50,"totalTokenCount":150}}"#
        let data = Data(json.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        let hasTokenUsage = events.contains { event in
            if case let .tokenUsage(_, prompt, completion, total) = event {
                return prompt == 100 && completion == 50 && total == 150
            }
            return false
        }
        #expect(hasTokenUsage)
    }
}

// MARK: - GeminiEventNormalizerNotificationTests

@Suite(.tags(.gemini))
struct GeminiEventNormalizerNotificationTests {
    @Test
    func `Notification with ToolPermission normalizes to permissionRequested`() throws {
        let json = #"{"hook_event_name":"Notification","session_id":"s1","# +
            #""notification_type":"ToolPermission","tool_name":"Bash","timestamp":"t1"}"#
        let data = Data(json.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        guard case let .permissionRequested(sid, request) = events.first else {
            Issue.record("Expected .permissionRequested, got \(String(describing: events.first))")
            return
        }
        #expect(sid == "s1")
        #expect(request.toolName == "Bash")
        // Request ID must match the composite key used by GeminiBridgeDelegate.extractRequestID
        // so that respondToPermission can find the held-open BeforeTool socket connection.
        #expect(request.id == "s1:Bash:t1")
    }

    @Test
    func `Notification without ToolPermission normalizes to notification`() throws {
        let json = #"{"hook_event_name":"Notification","session_id":"s1","message":"heads up"}"#
        let data = Data(json.utf8)
        let (events, _) = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        guard case let .notification(sid, message) = events.first else {
            Issue.record("Expected .notification")
            return
        }
        #expect(sid == "s1")
        #expect(message == "heads up")
    }
}

// MARK: - GeminiEventNormalizerErrorTests

@Suite(.tags(.gemini))
struct GeminiEventNormalizerErrorTests {
    @Test
    func `unknown event type throws unknownEventType`() {
        let data = Data(#"{"hook_event_name":"SomeNewEvent","session_id":"s1"}"#.utf8)
        #expect(throws: EventNormalizationError.self) {
            _ = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        }
    }

    @Test
    func `missing hook_event_name throws missingRequiredField`() {
        let data = Data(#"{"session_id":"s1"}"#.utf8)
        #expect(throws: EventNormalizationError.self) {
            _ = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        }
    }

    @Test
    func `missing session_id throws missingRequiredField`() {
        let data = Data(#"{"hook_event_name":"SessionStart"}"#.utf8)
        #expect(throws: EventNormalizationError.self) {
            _ = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        }
    }

    @Test
    func `invalid JSON throws malformedPayload`() {
        let data = Data("not json at all".utf8)
        #expect(throws: EventNormalizationError.self) {
            _ = try GeminiEventNormalizer.normalize(data, lastAfterModelTime: nil)
        }
    }
}
