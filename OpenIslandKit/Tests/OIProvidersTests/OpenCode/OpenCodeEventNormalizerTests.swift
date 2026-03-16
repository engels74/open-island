import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - OpenCodeEventNormalizerSessionTests

@Suite(.tags(.opencode))
struct OpenCodeEventNormalizerSessionTests {
    @Test
    func `session created normalizes to sessionStarted`() {
        let event = SSEEvent(event: "session.created", data: #"{"sessionId":"s1","directory":"/proj"}"#, id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
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
    func `session deleted normalizes to sessionEnded`() {
        let event = SSEEvent(event: "session.deleted", data: #"{"sessionId":"s1"}"#, id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        guard case let .sessionEnded(sid) = events.first else {
            Issue.record("Expected .sessionEnded")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `session status processing normalizes to processingStarted`() {
        let event = SSEEvent(event: "session.status", data: #"{"sessionId":"s1","status":"processing"}"#, id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        #expect(events.count == 1)
        guard case let .processingStarted(sid) = events.first else {
            Issue.record("Expected .processingStarted, got \(String(describing: events.first))")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `session status non-processing returns empty`() {
        let event = SSEEvent(event: "session.status", data: #"{"sessionId":"s1","status":"idle"}"#, id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        #expect(events.isEmpty)
    }

    @Test
    func `session idle normalizes to waitingForInput`() {
        let event = SSEEvent(event: "session.idle", data: #"{"sessionId":"s1"}"#, id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        guard case let .waitingForInput(sid) = events.first else {
            Issue.record("Expected .waitingForInput")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `session compacted normalizes to compacting`() {
        let event = SSEEvent(event: "session.compacted", data: #"{"sessionId":"s1"}"#, id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        guard case let .compacting(sid) = events.first else {
            Issue.record("Expected .compacting")
            return
        }
        #expect(sid == "s1")
    }

    @Test
    func `session error normalizes to notification`() {
        let event = SSEEvent(event: "session.error", data: #"{"sessionId":"s1","error":"Something broke"}"#, id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        guard case let .notification(sid, message) = events.first else {
            Issue.record("Expected .notification")
            return
        }
        #expect(sid == "s1")
        #expect(message == "Something broke")
    }

    @Test
    func `session diff normalizes to diffUpdated`() {
        let event = SSEEvent(event: "session.diff", data: #"{"sessionId":"s1","diff":"--- a/f\n+++ b/f"}"#, id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        guard case let .diffUpdated(sid, diff) = events.first else {
            Issue.record("Expected .diffUpdated")
            return
        }
        #expect(sid == "s1")
        #expect(diff == "--- a/f\n+++ b/f")
    }
}

// MARK: - OpenCodeEventNormalizerToolTests

@Suite(.tags(.opencode))
struct OpenCodeEventNormalizerToolTests {
    @Test
    func `tool execute before normalizes to toolStarted`() {
        let event = SSEEvent(
            event: "tool.execute.before",
            data: #"{"sessionId":"s1","toolId":"t1","tool":"Bash","input":{"command":"ls"}}"#,
            id: nil,
        )
        let events = OpenCodeEventNormalizer.normalize(event)
        guard case let .toolStarted(sid, toolEvent) = events.first else {
            Issue.record("Expected .toolStarted")
            return
        }
        #expect(sid == "s1")
        #expect(toolEvent.name == "Bash")
    }

    @Test
    func `tool execute after success normalizes to toolCompleted`() {
        let event = SSEEvent(
            event: "tool.execute.after",
            data: #"{"sessionId":"s1","toolId":"t1","tool":"Read","result":"file content"}"#,
            id: nil,
        )
        let events = OpenCodeEventNormalizer.normalize(event)
        guard case let .toolCompleted(sid, toolEvent, toolResult) = events.first else {
            Issue.record("Expected .toolCompleted")
            return
        }
        #expect(sid == "s1")
        #expect(toolEvent.name == "Read")
        #expect(toolResult?.isSuccess == true)
    }

    @Test
    func `tool execute after failure normalizes to toolCompleted with error`() {
        let event = SSEEvent(
            event: "tool.execute.after",
            data: #"{"sessionId":"s1","tool":"Bash","error":"Permission denied"}"#,
            id: nil,
        )
        let events = OpenCodeEventNormalizer.normalize(event)
        guard case let .toolCompleted(_, _, toolResult) = events.first else {
            Issue.record("Expected .toolCompleted")
            return
        }
        #expect(toolResult?.isSuccess == false)
        #expect(toolResult?.errorMessage == "Permission denied")
    }
}

// MARK: - OpenCodeEventNormalizerPermissionTests

@Suite(.tags(.opencode))
struct OpenCodeEventNormalizerPermissionTests {
    @Test
    func `permission asked normalizes to permissionRequested with requestId`() {
        let event = SSEEvent(
            event: "permission.asked",
            data: #"{"sessionId":"s1","requestId":"perm-1","tool":"Bash","input":{"command":"rm -rf"}}"#,
            id: nil,
        )
        let events = OpenCodeEventNormalizer.normalize(event)
        guard case let .permissionRequested(sid, request) = events.first else {
            Issue.record("Expected .permissionRequested")
            return
        }
        #expect(sid == "s1")
        #expect(request.id == "perm-1")
        #expect(request.toolName == "Bash")
    }

    @Test
    func `permission asked with risk extracts risk level`() {
        let event = SSEEvent(
            event: "permission.asked",
            data: #"{"sessionId":"s1","requestId":"perm-2","tool":"Bash","risk":"high"}"#,
            id: nil,
        )
        let events = OpenCodeEventNormalizer.normalize(event)
        guard case let .permissionRequested(_, request) = events.first else {
            Issue.record("Expected .permissionRequested")
            return
        }
        #expect(request.risk == .high)
    }
}

// MARK: - OpenCodeEventNormalizerMessageTests

@Suite(.tags(.opencode))
struct OpenCodeEventNormalizerMessageTests {
    @Test
    func `message part updated normalizes to modelResponse`() {
        let event = SSEEvent(
            event: "message.part.updated",
            data: #"{"sessionId":"s1","delta":"Hello world"}"#,
            id: nil,
        )
        let events = OpenCodeEventNormalizer.normalize(event)
        guard case let .modelResponse(sid, textDelta) = events.first else {
            Issue.record("Expected .modelResponse")
            return
        }
        #expect(sid == "s1")
        #expect(textDelta == "Hello world")
    }

    @Test
    func `message part updated without delta returns empty`() {
        let event = SSEEvent(
            event: "message.part.updated",
            data: #"{"sessionId":"s1"}"#,
            id: nil,
        )
        let events = OpenCodeEventNormalizer.normalize(event)
        #expect(events.isEmpty)
    }

    @Test
    func `message updated normalizes to chatUpdated`() {
        let json = #"{"sessionId":"s1","content":[{"role":"assistant","text":"Hi there","id":"m1"}]}"#
        let event = SSEEvent(event: "message.updated", data: json, id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        guard case let .chatUpdated(sid, items) = events.first else {
            Issue.record("Expected .chatUpdated")
            return
        }
        #expect(sid == "s1")
        #expect(items.count == 1)
        #expect(items.first?.content == "Hi there")
        #expect(items.first?.type == .assistant)
    }

    @Test
    func `message updated without content returns empty`() {
        let event = SSEEvent(event: "message.updated", data: #"{"sessionId":"s1"}"#, id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        #expect(events.isEmpty)
    }
}

// MARK: - OpenCodeEventNormalizerFileTests

@Suite(.tags(.opencode))
struct OpenCodeEventNormalizerFileTests {
    @Test
    func `file edited normalizes to notification`() {
        let event = SSEEvent(event: "file.edited", data: #"{"sessionId":"s1","path":"/src/main.swift"}"#, id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        guard case let .notification(sid, message) = events.first else {
            Issue.record("Expected .notification")
            return
        }
        #expect(sid == "s1")
        #expect(message.contains("main.swift"))
    }
}

// MARK: - OpenCodeEventNormalizerEdgeCaseTests

@Suite(.tags(.opencode))
struct OpenCodeEventNormalizerEdgeCaseTests {
    @Test
    func `unknown event type returns empty array`() {
        let event = SSEEvent(event: "some.unknown.event", data: #"{"sessionId":"s1"}"#, id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        #expect(events.isEmpty)
    }

    @Test
    func `nil event type returns empty array`() {
        let event = SSEEvent(event: nil, data: #"{"sessionId":"s1"}"#, id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        #expect(events.isEmpty)
    }

    @Test
    func `invalid JSON data returns empty array`() {
        let event = SSEEvent(event: "session.created", data: "not valid json", id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        #expect(events.isEmpty)
    }

    @Test
    func `empty JSON data returns empty array`() {
        let event = SSEEvent(event: "session.created", data: "", id: nil)
        let events = OpenCodeEventNormalizer.normalize(event)
        #expect(events.isEmpty)
    }
}
