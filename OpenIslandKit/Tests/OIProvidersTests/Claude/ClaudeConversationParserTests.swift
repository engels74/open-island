import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - JSONL Builders (file-scope helpers)

private func humanLine(
    text: String,
    uuid: String,
    ts: String = "2025-01-15T10:00:00Z",
) -> String {
    """
    {"type":"human","message":{"role":"user",\
    "content":[{"type":"text","text":"\(text)"}]},\
    "timestamp":"\(ts)","uuid":"\(uuid)"}
    """
}

private func assistantLine(
    text: String,
    uuid: String,
    stopReason: String = "end_turn",
    ts: String = "2025-01-15T10:00:00Z",
) -> String {
    """
    {"type":"assistant","message":{"role":"assistant",\
    "content":[{"type":"text","text":"\(text)"}],\
    "stop_reason":"\(stopReason)"},\
    "timestamp":"\(ts)","uuid":"\(uuid)"}
    """
}

private func assistantWithToolLine(
    text: String,
    toolName: String,
    toolID: String,
    toolInput: String,
    uuid: String,
    ts: String = "2025-01-15T10:00:00Z",
) -> String {
    """
    {"type":"assistant","message":{"role":"assistant",\
    "content":[{"type":"text","text":"\(text)"},\
    {"type":"tool_use","id":"\(toolID)",\
    "name":"\(toolName)","input":\(toolInput)}],\
    "stop_reason":"tool_use"},\
    "timestamp":"\(ts)","uuid":"\(uuid)"}
    """
}

private func assistantWithThinkingLine(
    thinking: String,
    text: String,
    uuid: String,
    ts: String = "2025-01-15T10:00:00Z",
) -> String {
    """
    {"type":"assistant","message":{"role":"assistant",\
    "content":[{"type":"thinking",\
    "thinking":"\(thinking)"},\
    {"type":"text","text":"\(text)"}],\
    "stop_reason":"end_turn"},\
    "timestamp":"\(ts)","uuid":"\(uuid)"}
    """
}

// MARK: - File Helpers (file-scope)

private func writeTempJSONL(lines: [String]) throws -> String {
    let path = NSTemporaryDirectory()
        + "claude-test-\(UUID().uuidString).jsonl"
    let content = lines.joined(separator: "\n")
    try content.write(
        toFile: path,
        atomically: true,
        encoding: .utf8,
    )
    return path
}

private func appendToFile(path: String, line: String) {
    guard let handle = FileHandle(forWritingAtPath: path)
    else { return }
    defer { try? handle.close() }
    handle.seekToEndOfFile()
    if let data = ("\n" + line).data(using: .utf8) {
        handle.write(data)
    }
}

private func removeTempFile(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
}

// MARK: - ClaudeConversationParserJSONLTests

struct ClaudeConversationParserJSONLTests {
    @Test
    func `Parse human message`() async throws {
        let parser = ClaudeConversationParser()
        let path = try writeTempJSONL(lines: [
            humanLine(text: "hello world", uuid: "msg-1"),
        ])
        defer { removeTempFile(path) }

        let items = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(items.count == 1)
        #expect(items[0].type == .user)
        #expect(items[0].content == "hello world")
        #expect(items[0].id == "msg-1")
    }

    @Test
    func `Parse assistant text message`() async throws {
        let parser = ClaudeConversationParser()
        let path = try writeTempJSONL(lines: [
            assistantLine(
                text: "Hi there!",
                uuid: "msg-2",
                stopReason: "end_turn",
            ),
        ])
        defer { removeTempFile(path) }

        let items = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(items.count == 1)
        #expect(items[0].type == .assistant)
        #expect(items[0].content == "Hi there!")
        #expect(items[0].id == "msg-2")
    }

    @Test
    func `Parse assistant with tool use`() async throws {
        let parser = ClaudeConversationParser()
        let jsonl = assistantWithToolLine(
            text: "Let me check.",
            toolName: "Bash",
            toolID: "tu-1",
            toolInput: #"{"command":"ls -la"}"#,
            uuid: "msg-3",
        )
        let path = try writeTempJSONL(lines: [jsonl])
        defer { removeTempFile(path) }

        let items = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(items.count == 2)
        #expect(items[0].type == .assistant)
        #expect(items[0].content == "Let me check.")
        #expect(items[0].id == "msg-3")
        #expect(items[1].type == .toolCall)
        #expect(items[1].content.contains("Bash"))
        #expect(items[1].content.contains("ls -la"))
        #expect(items[1].id == "msg-3-tool-0")
        #expect(items[1].providerSpecific != nil)
    }

    @Test
    func `Parse assistant with thinking block`() async throws {
        let parser = ClaudeConversationParser()
        let jsonl = assistantWithThinkingLine(
            thinking: "I need to analyze this...",
            text: "Here is my analysis.",
            uuid: "msg-4",
        )
        let path = try writeTempJSONL(lines: [jsonl])
        defer { removeTempFile(path) }

        let items = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(items.count == 2)
        #expect(items[0].type == .assistant)
        #expect(items[0].content == "Here is my analysis.")
        #expect(items[1].type == .thinking)
        #expect(items[1].content == "I need to analyze this...")
        #expect(items[1].id == "msg-4-thinking-0")
    }

    @Test
    func `Skip tool_result lines`() async throws {
        let parser = ClaudeConversationParser()
        let jsonl = """
        {"type":"tool_result","tool_use_id":"tu-1",\
        "content":[{"type":"text","text":"file1.txt"}],\
        "is_error":false,"timestamp":"2025-01-15T10:04:00Z"}
        """
        let path = try writeTempJSONL(lines: [jsonl])
        defer { removeTempFile(path) }

        let items = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(items.isEmpty)
    }

    @Test
    func `Skip summary lines`() async throws {
        let parser = ClaudeConversationParser()
        let jsonl = """
        {"type":"summary",\
        "summary":"Session summary text",\
        "timestamp":"2025-01-15T10:05:00Z"}
        """
        let path = try writeTempJSONL(lines: [jsonl])
        defer { removeTempFile(path) }

        let items = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(items.isEmpty)
    }

    @Test
    func `Multiple text blocks concatenate`() async throws {
        let parser = ClaudeConversationParser()
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant",\
        "content":[{"type":"text","text":"Part one."},\
        {"type":"text","text":"Part two."}],\
        "stop_reason":"end_turn"},\
        "timestamp":"2025-01-15T10:00:00Z","uuid":"msg-1"}
        """
        let path = try writeTempJSONL(lines: [jsonl])
        defer { removeTempFile(path) }

        let items = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(items.count == 1)
        #expect(items[0].type == .assistant)
        #expect(items[0].content == "Part one.\nPart two.")
    }
}

// MARK: - ClaudeConversationParserIncrementalTests

struct ClaudeConversationParserIncrementalTests {
    @Test
    func `Incremental parsing returns only new items`() async throws {
        let parser = ClaudeConversationParser()
        let path = try writeTempJSONL(lines: [
            humanLine(text: "first", uuid: "msg-1"),
        ])
        defer { removeTempFile(path) }

        let firstBatch = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(firstBatch.count == 1)
        #expect(firstBatch[0].content == "first")

        appendToFile(
            path: path,
            line: humanLine(
                text: "second",
                uuid: "msg-2",
                ts: "2025-01-15T10:01:00Z",
            ),
        )

        let secondBatch = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(secondBatch.count == 1)
        #expect(secondBatch[0].content == "second")

        let all = await parser.chatItems(for: "s1")
        #expect(all.count == 2)
    }

    @Test
    func `Detect file truncation and reset`() async throws {
        let parser = ClaudeConversationParser()
        let path = try writeTempJSONL(lines: [
            humanLine(text: "message one", uuid: "msg-1"),
            humanLine(
                text: "message two",
                uuid: "msg-2",
                ts: "2025-01-15T10:01:00Z",
            ),
        ])
        defer { removeTempFile(path) }

        let firstBatch = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(firstBatch.count == 2)

        // Truncate — replace file with shorter content
        let shorter = humanLine(
            text: "fresh start",
            uuid: "msg-3",
            ts: "2025-01-15T10:02:00Z",
        )
        try shorter.write(
            toFile: path,
            atomically: true,
            encoding: .utf8,
        )

        let afterTruncation = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(afterTruncation.count == 1)
        #expect(afterTruncation[0].content == "fresh start")

        let all = await parser.chatItems(for: "s1")
        #expect(all.count == 1)
    }

    @Test
    func `handleClear resets session chat items`() async throws {
        let parser = ClaudeConversationParser()
        let path = try writeTempJSONL(lines: [
            humanLine(text: "hello", uuid: "msg-1"),
        ])
        defer { removeTempFile(path) }

        _ = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        let before = await parser.chatItems(for: "s1")
        #expect(before.count == 1)

        await parser.handleClear(sessionID: "s1")

        let after = await parser.chatItems(for: "s1")
        #expect(after.isEmpty)
    }
}

// MARK: - ClaudeConversationParserEdgeCaseTests

struct ClaudeConversationParserEdgeCaseTests {
    @Test
    func `Invalid JSONL lines are skipped gracefully`() async throws {
        let parser = ClaudeConversationParser()
        let path = try writeTempJSONL(lines: [
            "not valid json at all",
            humanLine(text: "valid", uuid: "msg-1"),
            "{malformed: true,",
        ])
        defer { removeTempFile(path) }

        let items = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(items.count == 1)
        #expect(items[0].content == "valid")
    }

    @Test
    func `Empty file returns no items`() async throws {
        let parser = ClaudeConversationParser()
        let path = try writeTempJSONL(lines: [])
        defer { removeTempFile(path) }

        let items = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(items.isEmpty)
    }

    @Test
    func `Missing file throws fileNotFound`() async throws {
        let parser = ClaudeConversationParser()
        let fakePath = "/tmp/nonexistent-\(UUID().uuidString).jsonl"
        await #expect(throws: ConversationParseError.self) {
            try await parser.parseIncremental(
                sessionID: "s1",
                transcriptPath: fakePath,
            )
        }
    }

    @Test
    func `Parse sessions index file`() async throws {
        let parser = ClaudeConversationParser()
        let dir = NSTemporaryDirectory()
            + "claude-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
        )
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let indexJSON = """
        [
            {
                "session_id": "abc-123",
                "project_name": "my-project",
                "summary": "Working on auth",
                "message_count": 42,
                "git_branch": "main",
                "last_active_at": "2025-01-15T10:00:00Z"
            },
            {
                "session_id": "def-456",
                "project_name": "my-project",
                "summary": null,
                "message_count": null,
                "git_branch": null,
                "last_active_at": null
            }
        ]
        """
        try indexJSON.write(
            toFile: dir + "/sessions-index.json",
            atomically: true,
            encoding: .utf8,
        )

        let entries = try await parser.parseSessionsIndex(
            projectPath: dir,
        )
        #expect(entries.count == 2)
        #expect(entries[0].sessionID == "abc-123")
        #expect(entries[0].projectName == "my-project")
        #expect(entries[0].summary == "Working on auth")
        #expect(entries[0].messageCount == 42)
        #expect(entries[0].gitBranch == "main")
        #expect(entries[0].lastActiveAt != nil)
        #expect(entries[1].sessionID == "def-456")
        #expect(entries[1].summary == nil)
    }

    @Test
    func `Sessions index not found throws`() async throws {
        let parser = ClaudeConversationParser()
        let fakePath = "/tmp/nonexistent-\(UUID().uuidString)"
        await #expect(throws: ConversationParseError.self) {
            try await parser.parseSessionsIndex(
                projectPath: fakePath,
            )
        }
    }

    @Test
    func `Parse timestamp with fractional seconds`() async throws {
        let parser = ClaudeConversationParser()
        let path = try writeTempJSONL(lines: [
            humanLine(
                text: "hi",
                uuid: "msg-ts",
                ts: "2025-01-15T10:30:45.123Z",
            ),
        ])
        defer { removeTempFile(path) }

        let items = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(items.count == 1)
        let calendar = Calendar(identifier: .gregorian)
        let tz = try #require(TimeZone(identifier: "UTC"))
        let components = calendar.dateComponents(
            in: tz,
            from: items[0].timestamp,
        )
        #expect(components.year == 2025)
        #expect(components.month == 1)
        #expect(components.day == 15)
    }

    @Test
    func `Parse message with large content`() async throws {
        let parser = ClaudeConversationParser()
        let largeText = String(repeating: "x", count: 50000)
        let line = humanLine(
            text: largeText,
            uuid: "msg-large",
        )
        let path = try writeTempJSONL(lines: [line])
        defer { removeTempFile(path) }

        let items = try await parser.parseIncremental(
            sessionID: "s1",
            transcriptPath: path,
        )
        #expect(items.count == 1)
        #expect(items[0].content.count == 50000)
    }

    @Test
    func `chatItems returns empty for unknown session`() async {
        let parser = ClaudeConversationParser()
        let items = await parser.chatItems(for: "nonexistent")
        #expect(items.isEmpty)
    }
}
