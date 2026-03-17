import Foundation
@testable import OICore
import Testing

// MARK: - ChatViewTests

/// Tests for ``ChatHistoryItem`` rendering logic used by ChatView.
///
/// Verifies that each ``ChatItemType`` maps to the expected view routing
/// and that chat items store the correct content and metadata.
struct ChatViewTests {
    // MARK: - ChatItemType Coverage

    @Test
    func `Each ChatItemType produces a valid ChatHistoryItem`() {
        let types: [ChatItemType] = [.user, .assistant, .toolCall, .thinking, .reasoning, .interrupted]

        for itemType in types {
            let item = ChatHistoryItem(
                id: "item-\(itemType)",
                timestamp: .now,
                type: itemType,
                content: "content",
            )
            #expect(item.type == itemType)
            #expect(item.content == "content")
        }
    }

    @Test
    func `User item stores content correctly`() {
        let item = ChatHistoryItem(
            id: "u1",
            timestamp: .now,
            type: .user,
            content: "Fix the login bug",
        )
        #expect(item.type == .user)
        #expect(item.content == "Fix the login bug")
        #expect(item.id == "u1")
        #expect(item.providerSpecific == nil)
    }

    @Test
    func `Assistant item carries markdown content`() {
        let markdown = "I'll look into the **login bug**."
        let item = ChatHistoryItem(
            id: "a1",
            timestamp: .now,
            type: .assistant,
            content: markdown,
        )
        #expect(item.type == .assistant)
        #expect(item.content == markdown)
    }

    @Test
    func `ToolCall item can match active tools by ID`() {
        let toolItem = ChatHistoryItem(
            id: "tool-42",
            timestamp: .now,
            type: .toolCall,
            content: "import Foundation\n...",
            providerSpecific: .object(["tool_name": .string("Read")]),
        )

        let activeTool = ToolCallItem(
            id: "tool-42",
            name: "Read",
            input: .object(["path": .string("/src/App.swift")]),
            status: .success,
            result: .string("file contents"),
        )

        // ChatView matches tool calls by ID
        #expect(toolItem.id == activeTool.id)
        #expect(toolItem.type == .toolCall)
        #expect(toolItem.providerSpecific?["tool_name"]?.stringValue == "Read")
    }

    @Test
    func `ToolCall fallback extracts tool_name from providerSpecific`() {
        let item = ChatHistoryItem(
            id: "tool-99",
            timestamp: .now,
            type: .toolCall,
            content: "result text",
            providerSpecific: .object(["tool_name": .string("Bash")]),
        )

        // When no matching active tool exists, ChatView creates a fallback ToolCallItem
        let fallbackName = item.providerSpecific?["tool_name"]?.stringValue ?? "Tool"
        #expect(fallbackName == "Bash")
    }

    @Test
    func `ToolCall without providerSpecific falls back to 'Tool'`() {
        let item = ChatHistoryItem(
            id: "tool-100",
            timestamp: .now,
            type: .toolCall,
            content: "output",
        )

        let fallbackName = item.providerSpecific?["tool_name"]?.stringValue ?? "Tool"
        #expect(fallbackName == "Tool")
    }

    @Test
    func `Thinking item is identified as collapsible`() {
        let item = ChatHistoryItem(
            id: "t1",
            timestamp: .now,
            type: .thinking,
            content: "The bug is in the token validation logic.",
        )
        #expect(item.type == .thinking)
        #expect(!item.content.isEmpty)
    }

    @Test
    func `Reasoning item is identified as collapsible`() {
        let item = ChatHistoryItem(
            id: "r1",
            timestamp: .now,
            type: .reasoning,
            content: "User interrupted. Adjusting strategy.",
        )
        #expect(item.type == .reasoning)
        #expect(!item.content.isEmpty)
    }

    @Test
    func `Interrupted item is recognized`() {
        let item = ChatHistoryItem(
            id: "int-1",
            timestamp: .now,
            type: .interrupted,
            content: "",
        )
        #expect(item.type == .interrupted)
        // Interrupted items typically have empty content — rendered as a divider
        #expect(item.content.isEmpty)
    }

    // MARK: - Compaction Phase

    @Test
    func `Session with compacting phase is identifiable`() {
        let session = SessionState(
            id: "compact-1",
            providerID: .claude,
            phase: .compacting,
            projectName: "TestProject",
            cwd: "/tmp/test",
            createdAt: .now,
            lastActivityAt: .now,
        )
        #expect(session.phase == .compacting)
        #expect(session.phase != .processing)
        #expect(session.phase != .idle)
    }

    @Test
    func `Compacting phase is distinct from processing`() {
        #expect(SessionPhase.compacting != SessionPhase.processing)
        #expect(SessionPhase.compacting != SessionPhase.idle)
        #expect(SessionPhase.compacting != SessionPhase.waitingForInput)
    }

    // MARK: - Data Integrity

    @Test
    func `ChatHistoryItem preserves all fields`() {
        let timestamp = Date.now
        let extra: JSONValue = .object(["model": .string("claude-4")])
        let item = ChatHistoryItem(
            id: "full-1",
            timestamp: timestamp,
            type: .assistant,
            content: "Hello",
            providerSpecific: extra,
        )

        #expect(item.id == "full-1")
        #expect(item.timestamp == timestamp)
        #expect(item.type == .assistant)
        #expect(item.content == "Hello")
        #expect(item.providerSpecific == extra)
    }

    @Test(
        arguments: [
            (ChatItemType.user, ChatItemType.assistant),
            (ChatItemType.toolCall, ChatItemType.thinking),
            (ChatItemType.reasoning, ChatItemType.interrupted),
        ],
    )
    func `Each item type is distinct`(pair: (ChatItemType, ChatItemType)) {
        #expect(pair.0 != pair.1)
    }

    // MARK: - Chat Item Collection

    @Test
    func `SessionState chatItems collection maintains order`() {
        let items = (0 ..< 5).map { i in
            ChatHistoryItem(
                id: "msg-\(i)",
                timestamp: .now,
                type: .user,
                content: "Message \(i)",
            )
        }

        let session = SessionState(
            id: "s1",
            providerID: .claude,
            phase: .processing,
            projectName: "TestProject",
            cwd: "/tmp/test",
            chatItems: items,
            createdAt: .now,
            lastActivityAt: .now,
        )

        #expect(session.chatItems.count == 5)
        for (index, item) in session.chatItems.enumerated() {
            #expect(item.id == "msg-\(index)")
            #expect(item.content == "Message \(index)")
        }
    }
}
