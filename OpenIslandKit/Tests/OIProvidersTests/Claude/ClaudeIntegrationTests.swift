import Darwin
import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - IntegrationFixture

/// Fixture for parameterized end-to-end event tests.
///
/// Each fixture pairs a raw JSON payload with the expected ``ProviderEvent`` case name
/// that the adapter should emit (or `nil` for events with no ``ProviderEvent`` equivalent).
struct IntegrationFixture: Sendable, CustomTestStringConvertible {
    let eventName: String
    let json: String
    /// Expected ProviderEvent case label, or nil if the event should be filtered out.
    let expectedCase: String?

    var testDescription: String {
        self.eventName
    }
}

// MARK: - All 18 Fixtures

private let allIntegrationFixtures: [IntegrationFixture] = [
    // Session events → mapped
    IntegrationFixture(
        eventName: "SessionStart",
        json: #"{"session_id":"int-1","hook_event_name":"SessionStart","cwd":"/proj","session_type":"startup"}"#,
        expectedCase: "sessionStarted",
    ),
    IntegrationFixture(
        eventName: "SessionEnd",
        json: #"{"session_id":"int-1","hook_event_name":"SessionEnd"}"#,
        expectedCase: "sessionEnded",
    ),
    IntegrationFixture(
        eventName: "UserPromptSubmit",
        json: #"{"session_id":"int-1","hook_event_name":"UserPromptSubmit"}"#,
        expectedCase: "userPromptSubmitted",
    ),
    IntegrationFixture(
        eventName: "Stop",
        json: #"{"session_id":"int-1","hook_event_name":"Stop"}"#,
        expectedCase: "waitingForInput",
    ),
    IntegrationFixture(
        eventName: "PreCompact",
        json: #"{"session_id":"int-1","hook_event_name":"PreCompact","compaction_reason":"full","message_count":100}"#,
        expectedCase: "compacting",
    ),
    IntegrationFixture(
        eventName: "ConfigChange",
        json: #"{"session_id":"int-1","hook_event_name":"ConfigChange"}"#,
        expectedCase: "configChanged",
    ),
    IntegrationFixture(
        eventName: "Notification",
        json: #"{"session_id":"int-1","hook_event_name":"Notification","message":"heads up"}"#,
        expectedCase: "notification",
    ),
    // Tool events → mapped
    IntegrationFixture(
        eventName: "PreToolUse",
        json: #"{"session_id":"int-1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_use_id":"tu-1"}"#,
        expectedCase: "toolStarted",
    ),
    IntegrationFixture(
        eventName: "PostToolUse",
        json: #"{"session_id":"int-1","hook_event_name":"PostToolUse","tool_name":"Read","tool_use_id":"tu-2","tool_result":{"content":"data"}}"#,
        expectedCase: "toolCompleted",
    ),
    IntegrationFixture(
        eventName: "PostToolUseFailure",
        json: #"{"session_id":"int-1","hook_event_name":"PostToolUseFailure","tool_name":"Write","tool_use_id":"tu-3","error":"Permission denied"}"#,
        expectedCase: "toolCompleted",
    ),
    IntegrationFixture(
        eventName: "PermissionRequest",
        json: #"{"session_id":"int-1","hook_event_name":"PermissionRequest","tool_name":"Bash""#
            + #","tool_input":{"command":"rm -rf /tmp"},"tool_use_id":"tu-4"}"#,
        expectedCase: "permissionRequested",
    ),
    // Subagent events → mapped
    IntegrationFixture(
        eventName: "SubagentStart",
        json: #"{"session_id":"int-1","hook_event_name":"SubagentStart","task_id":"task-1"}"#,
        expectedCase: "subagentStarted",
    ),
    IntegrationFixture(
        eventName: "SubagentStop",
        json: #"{"session_id":"int-1","hook_event_name":"SubagentStop","task_id":"task-1"}"#,
        expectedCase: "subagentStopped",
    ),
    // Nil-mapped events → no ProviderEvent emitted
    IntegrationFixture(
        eventName: "Setup",
        json: #"{"session_id":"int-1","hook_event_name":"Setup","cwd":"/proj"}"#,
        expectedCase: nil,
    ),
    IntegrationFixture(
        eventName: "TeammateIdle",
        json: #"{"session_id":"int-1","hook_event_name":"TeammateIdle"}"#,
        expectedCase: nil,
    ),
    IntegrationFixture(
        eventName: "TaskCompleted",
        json: #"{"session_id":"int-1","hook_event_name":"TaskCompleted","task_id":"task-1"}"#,
        expectedCase: nil,
    ),
    IntegrationFixture(
        eventName: "WorktreeCreate",
        json: #"{"session_id":"int-1","hook_event_name":"WorktreeCreate"}"#,
        expectedCase: nil,
    ),
    IntegrationFixture(
        eventName: "WorktreeRemove",
        json: #"{"session_id":"int-1","hook_event_name":"WorktreeRemove"}"#,
        expectedCase: nil,
    ),
]

/// Subset: only fixtures that produce a ProviderEvent (13 of 18).
private let mappedFixtures = allIntegrationFixtures.filter { $0.expectedCase != nil }

/// Subset: only fixtures that produce nil (5 of 18).
private let nilMappedFixtures = allIntegrationFixtures.filter { $0.expectedCase == nil }

// MARK: - ClaudeIntegrationTests

/// Integration tests that verify cross-component flows through the Claude provider adapter.
///
/// These tests exercise the full pipeline: raw socket bytes → JSON decode → normalize → ProviderEvent stream.
/// They complement the per-component unit tests in sibling files.
@Suite(.tags(.claude, .socket), .serialized)
struct ClaudeIntegrationTests {
    // MARK: - 1. Full Session Lifecycle

    @Test(.timeLimit(.minutes(1)))
    func `full session lifecycle emits correct event sequence`() async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)
        try await adapter.start()
        defer { Task { await adapter.stop() } }

        let stream = adapter.events()

        // Allow socket server to be ready
        try await Task.sleep(for: .milliseconds(50))

        // Send a realistic multi-event session sequence
        let events = [
            #"{"session_id":"lifecycle-1","hook_event_name":"SessionStart","cwd":"/proj","session_type":"startup"}"#,
            #"{"session_id":"lifecycle-1","hook_event_name":"UserPromptSubmit"}"#,
            #"{"session_id":"lifecycle-1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"tu-1","tool_input":{"command":"ls"}}"#,
            #"{"session_id":"lifecycle-1","hook_event_name":"PostToolUse""#
                + #","tool_name":"Bash","tool_use_id":"tu-1","tool_result":{"output":"file.txt"}}"#,
            #"{"session_id":"lifecycle-1","hook_event_name":"Stop"}"#,
            #"{"session_id":"lifecycle-1","hook_event_name":"SessionEnd"}"#,
        ]

        for json in events {
            sendToSocket(path: path, data: Data((json + "\n").utf8))
            // Small delay between events to ensure ordering
            try await Task.sleep(for: .milliseconds(20))
        }

        // Collect all 6 events
        var received: [String] = []
        for await event in stream {
            received.append(providerEventCaseName(event))
            if received.count == 6 { break }
        }

        #expect(received == [
            "sessionStarted",
            "userPromptSubmitted",
            "toolStarted",
            "toolCompleted",
            "waitingForInput",
            "sessionEnded",
        ])
    }

    // MARK: - 2. All 18 Event Types End-to-End (parameterized)

    @Test(.timeLimit(.minutes(1)), arguments: mappedFixtures)
    func `mapped event types emit correct ProviderEvent through adapter`(
        fixture: IntegrationFixture,
    ) async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)
        try await adapter.start()
        defer { Task { await adapter.stop() } }

        let stream = adapter.events()
        try await Task.sleep(for: .milliseconds(50))

        sendToSocket(path: path, data: Data((fixture.json + "\n").utf8))

        var received: ProviderEvent?
        for await event in stream {
            received = event
            break
        }

        let event = try #require(received, "Expected adapter to emit an event for \(fixture.eventName)")
        #expect(providerEventCaseName(event) == fixture.expectedCase)
    }

    @Test(.timeLimit(.minutes(1)), arguments: nilMappedFixtures)
    func `nil-mapped event types produce no ProviderEvent through adapter`(
        fixture: IntegrationFixture,
    ) async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)
        try await adapter.start()
        defer { Task { await adapter.stop() } }

        let stream = adapter.events()
        try await Task.sleep(for: .milliseconds(50))

        // Send the nil-mapped event, then a known-good event as a sentinel
        sendToSocket(path: path, data: Data((fixture.json + "\n").utf8))
        try await Task.sleep(for: .milliseconds(20))

        let sentinel = #"{"session_id":"sentinel","hook_event_name":"Stop"}"# + "\n"
        sendToSocket(path: path, data: Data(sentinel.utf8))

        // The first event we receive should be the sentinel, not the nil-mapped event
        var received: ProviderEvent?
        for await event in stream {
            received = event
            break
        }

        let event = try #require(received)
        if case let .waitingForInput(sid) = event {
            #expect(sid == "sentinel")
        } else {
            Issue.record("Expected sentinel .waitingForInput, got \(providerEventCaseName(event))")
        }
    }

    // MARK: - 3. Permission Event Emission

    @Test(.timeLimit(.minutes(1)))
    func `permission request event flows through adapter with correct fields`() async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)
        try await adapter.start()
        defer { Task { await adapter.stop() } }

        let stream = adapter.events()
        try await Task.sleep(for: .milliseconds(50))

        let json = #"{"session_id":"perm-1","hook_event_name":"PermissionRequest""#
            + #","tool_name":"Bash","tool_input":{"command":"rm -rf /"},"tool_use_id":"perm-req-1"}"#
            + "\n"
        sendToSocket(path: path, data: Data(json.utf8))

        var received: ProviderEvent?
        for await event in stream {
            received = event
            break
        }

        let event = try #require(received)
        guard case let .permissionRequested(sid, request) = event else {
            Issue.record("Expected .permissionRequested, got \(providerEventCaseName(event))")
            return
        }
        #expect(sid == "perm-1")
        #expect(request.toolName == "Bash")
        #expect(request.id == "perm-req-1")
        #expect(request.toolInput?["command"]?.stringValue == "rm -rf /")
    }

    // MARK: - 4. Multiple Concurrent Sessions

    @Test(.timeLimit(.minutes(1)))
    func `events from multiple sessions arrive with correct session IDs`() async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)
        try await adapter.start()
        defer { Task { await adapter.stop() } }

        let stream = adapter.events()
        try await Task.sleep(for: .milliseconds(50))

        // Send events from three different sessions
        let payloads = [
            #"{"session_id":"session-A","hook_event_name":"SessionStart","cwd":"/a"}"#,
            #"{"session_id":"session-B","hook_event_name":"SessionStart","cwd":"/b"}"#,
            #"{"session_id":"session-C","hook_event_name":"SessionStart","cwd":"/c"}"#,
            #"{"session_id":"session-A","hook_event_name":"Stop"}"#,
            #"{"session_id":"session-B","hook_event_name":"SessionEnd"}"#,
        ]

        for json in payloads {
            sendToSocket(path: path, data: Data((json + "\n").utf8))
            try await Task.sleep(for: .milliseconds(20))
        }

        // Collect 5 events
        var sessionIDs: [String] = []
        for await event in stream {
            sessionIDs.append(providerEventSessionID(event))
            if sessionIDs.count == 5 { break }
        }

        #expect(sessionIDs == ["session-A", "session-B", "session-C", "session-A", "session-B"])
    }

    // MARK: - 5. Malformed Event Resilience

    @Test(.timeLimit(.minutes(1)))
    func `malformed JSON is skipped and valid events still arrive`() async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)
        try await adapter.start()
        defer { Task { await adapter.stop() } }

        let stream = adapter.events()
        try await Task.sleep(for: .milliseconds(50))

        // Send malformed JSON first
        sendToSocket(path: path, data: Data("{ this is not valid json }\n".utf8))
        try await Task.sleep(for: .milliseconds(30))

        // Then send a valid event
        let valid = #"{"session_id":"recover-1","hook_event_name":"Stop"}"# + "\n"
        sendToSocket(path: path, data: Data(valid.utf8))

        var received: ProviderEvent?
        for await event in stream {
            received = event
            break
        }

        let event = try #require(received)
        if case let .waitingForInput(sid) = event {
            #expect(sid == "recover-1")
        } else {
            Issue.record("Expected .waitingForInput after malformed JSON, got \(providerEventCaseName(event))")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `truncated JSON is skipped and valid events still arrive`() async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)
        try await adapter.start()
        defer { Task { await adapter.stop() } }

        let stream = adapter.events()
        try await Task.sleep(for: .milliseconds(50))

        // Send truncated JSON (missing closing brace)
        sendToSocket(path: path, data: Data(#"{"session_id":"s1","hook_event_name":"Stop"#.utf8))
        try await Task.sleep(for: .milliseconds(30))

        // Then send valid
        let valid = #"{"session_id":"recover-2","hook_event_name":"SessionEnd"}"# + "\n"
        sendToSocket(path: path, data: Data(valid.utf8))

        var received: ProviderEvent?
        for await event in stream {
            received = event
            break
        }

        let event = try #require(received)
        if case let .sessionEnded(sid) = event {
            #expect(sid == "recover-2")
        } else {
            Issue.record("Expected .sessionEnded after truncated JSON, got \(providerEventCaseName(event))")
        }
    }

    // MARK: - 6. Tool Event Field Preservation

    @Test(.timeLimit(.minutes(1)))
    func `tool event fields are preserved through the full pipeline`() async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)
        try await adapter.start()
        defer { Task { await adapter.stop() } }

        let stream = adapter.events()
        try await Task.sleep(for: .milliseconds(50))

        // PreToolUse with detailed fields
        let preToolJSON = #"{"session_id":"fields-1","hook_event_name":"PreToolUse""#
            + #","tool_name":"Edit","tool_use_id":"edit-001""#
            + #","tool_input":{"file_path":"/src/main.swift","old_string":"foo","new_string":"bar"}}"#
            + "\n"
        sendToSocket(path: path, data: Data(preToolJSON.utf8))

        try await Task.sleep(for: .milliseconds(20))

        // PostToolUse with result
        let postToolJSON =
            #"{"session_id":"fields-1","hook_event_name":"PostToolUse","tool_name":"Edit","tool_use_id":"edit-001","tool_result":{"success":true}}"# +
            "\n"
        sendToSocket(path: path, data: Data(postToolJSON.utf8))

        var events: [ProviderEvent] = []
        for await event in stream {
            events.append(event)
            if events.count == 2 { break }
        }

        // Verify PreToolUse fields
        guard case let .toolStarted(sid1, toolEvent1) = events[0] else {
            Issue.record("Expected .toolStarted")
            return
        }
        #expect(sid1 == "fields-1")
        #expect(toolEvent1.name == "Edit")
        #expect(toolEvent1.id == "edit-001")
        #expect(toolEvent1.input?["file_path"]?.stringValue == "/src/main.swift")
        #expect(toolEvent1.input?["old_string"]?.stringValue == "foo")
        #expect(toolEvent1.input?["new_string"]?.stringValue == "bar")

        // Verify PostToolUse fields
        guard case let .toolCompleted(sid2, toolEvent2, result) = events[1] else {
            Issue.record("Expected .toolCompleted")
            return
        }
        #expect(sid2 == "fields-1")
        #expect(toolEvent2.name == "Edit")
        #expect(result?.isSuccess == true)
    }

    // MARK: - 7. Adapter Stream Lifecycle

    @Test(.timeLimit(.minutes(1)))
    func `stop finishes the event stream`() async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)
        try await adapter.start()

        let stream = adapter.events()

        // Send one event so the stream has data
        try await Task.sleep(for: .milliseconds(50))
        let json = #"{"session_id":"s1","hook_event_name":"Stop"}"# + "\n"
        sendToSocket(path: path, data: Data(json.utf8))

        // Read the event
        var count = 0
        for await _ in stream {
            count += 1
            // Stop the adapter after receiving the first event
            await adapter.stop()
        }

        // Stream should have ended after stop — we got exactly 1 event
        #expect(count == 1)
    }

    // MARK: - 8. Subagent Events End-to-End

    @Test(.timeLimit(.minutes(1)))
    func `subagent start and stop events flow through adapter`() async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)
        try await adapter.start()
        defer { Task { await adapter.stop() } }

        let stream = adapter.events()
        try await Task.sleep(for: .milliseconds(50))

        let start = #"{"session_id":"sub-1","hook_event_name":"SubagentStart","task_id":"task-abc"}"# + "\n"
        sendToSocket(path: path, data: Data(start.utf8))
        try await Task.sleep(for: .milliseconds(20))

        let stop = #"{"session_id":"sub-1","hook_event_name":"SubagentStop","task_id":"task-abc"}"# + "\n"
        sendToSocket(path: path, data: Data(stop.utf8))

        var events: [ProviderEvent] = []
        for await event in stream {
            events.append(event)
            if events.count == 2 { break }
        }

        guard case let .subagentStarted(sid1, taskID1, _) = events[0] else {
            Issue.record("Expected .subagentStarted")
            return
        }
        #expect(sid1 == "sub-1")
        #expect(taskID1 == "task-abc")

        guard case let .subagentStopped(sid2, taskID2) = events[1] else {
            Issue.record("Expected .subagentStopped")
            return
        }
        #expect(sid2 == "sub-1")
        #expect(taskID2 == "task-abc")
    }
}

// MARK: - Helpers

/// Generate a unique socket path to avoid test interference.
private func uniqueSocketPath() -> String {
    "/tmp/oi-test-integ-\(UUID().uuidString.prefix(8)).sock"
}

/// Connect to a Unix domain socket and send data, then close.
private func sendToSocket(path: String, data: Data) {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = path.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
            pathBytes.withUnsafeBufferPointer { src in
                guard let srcBase = src.baseAddress else { return }
                _ = memcpy(dest, srcBase, src.count)
            }
        }
    }

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard connectResult == 0 else {
        Darwin.close(fd)
        return
    }

    data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        _ = Darwin.write(fd, base, buffer.count)
    }

    Darwin.close(fd)
}

/// Extract the case name from a ProviderEvent for assertion purposes.
private func providerEventCaseName(_ event: ProviderEvent) -> String { // swiftlint:disable:this cyclomatic_complexity
    switch event {
    case .sessionStarted: "sessionStarted"
    case .sessionEnded: "sessionEnded"
    case .userPromptSubmitted: "userPromptSubmitted"
    case .processingStarted: "processingStarted"
    case .toolStarted: "toolStarted"
    case .toolCompleted: "toolCompleted"
    case .permissionRequested: "permissionRequested"
    case .waitingForInput: "waitingForInput"
    case .compacting: "compacting"
    case .notification: "notification"
    case .chatUpdated: "chatUpdated"
    case .subagentStarted: "subagentStarted"
    case .subagentStopped: "subagentStopped"
    case .configChanged: "configChanged"
    case .diffUpdated: "diffUpdated"
    case .modelResponse: "modelResponse"
    case .tokenUsage: "tokenUsage"
    }
}

/// Extract the session ID from a ProviderEvent.
private func providerEventSessionID(_ event: ProviderEvent) -> String { // swiftlint:disable:this cyclomatic_complexity
    switch event {
    case let .sessionStarted(sid, _, _): sid
    case let .sessionEnded(sid): sid
    case let .userPromptSubmitted(sid): sid
    case let .processingStarted(sid): sid
    case let .toolStarted(sid, _): sid
    case let .toolCompleted(sid, _, _): sid
    case let .permissionRequested(sid, _): sid
    case let .waitingForInput(sid): sid
    case let .compacting(sid): sid
    case let .notification(sid, _): sid
    case let .chatUpdated(sid, _): sid
    case let .subagentStarted(sid, _, _): sid
    case let .subagentStopped(sid, _): sid
    case let .configChanged(sid): sid ?? ""
    case let .diffUpdated(sid, _): sid
    case let .modelResponse(sid, _): sid
    case let .tokenUsage(sid, _, _, _): sid
    }
}
