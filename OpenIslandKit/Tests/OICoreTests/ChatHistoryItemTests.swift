import Foundation
@testable import OICore
import Testing

struct ChatHistoryItemTests {
    @Test
    func `Basic construction and identity`() {
        let timestamp = Date.now
        let item = ChatHistoryItem(
            id: "msg-001",
            timestamp: timestamp,
            type: .user,
            content: "Hello",
        )
        #expect(item.id == "msg-001")
        #expect(item.timestamp == timestamp)
        #expect(item.type == .user)
        #expect(item.content == "Hello")
        #expect(item.providerSpecific == nil)
    }

    @Test
    func `Construction with provider-specific data`() {
        let extra: JSONValue = ["model": "claude-4", "stop_reason": "end_turn"]
        let item = ChatHistoryItem(
            id: "msg-002",
            timestamp: .now,
            type: .assistant,
            content: "Hi there!",
            providerSpecific: extra,
        )
        #expect(item.providerSpecific?["model"]?.stringValue == "claude-4")
        #expect(item.providerSpecific?["stop_reason"]?.stringValue == "end_turn")
    }

    @Test
    func `All chat item types`() {
        let types: [ChatItemType] = [.user, .assistant, .toolCall, .thinking, .interrupted, .reasoning]
        for itemType in types {
            let item = ChatHistoryItem(id: "t", timestamp: .now, type: itemType, content: "")
            #expect(item.type == itemType)
        }
    }

    @Test
    func `ChatItemType equality`() {
        let userType: ChatItemType = .user
        let sameUserType: ChatItemType = .user
        #expect(userType == sameUserType)
        let assistantType: ChatItemType = .assistant
        let sameAssistantType: ChatItemType = .assistant
        #expect(assistantType == sameAssistantType)
        #expect(ChatItemType.user != ChatItemType.assistant)
        #expect(ChatItemType.toolCall != ChatItemType.thinking)
    }

    @Test
    func `Identifiable conformance uses id`() {
        let item = ChatHistoryItem(id: "unique-id", timestamp: .now, type: .user, content: "test")
        #expect(item.id == "unique-id")
    }
}
