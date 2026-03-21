import Foundation
package import OICore

// MARK: - RolloutParseState

package struct RolloutParseState: Sendable {
    package var lastFileOffset: UInt64 = 0
    /// Used for truncation detection — if current size < last size, the file was rewritten.
    package var lastFileSize: UInt64 = 0
    package var chatItems: [ChatHistoryItem] = []
}

// MARK: - RolloutParseError

package enum RolloutParseError: Error, Sendable {
    case fileNotFound(String)
    case readFailed(String)
}

// MARK: - CodexSessionRolloutParser

/// Incrementally parses Codex session rollout JSONL files into ``ChatHistoryItem`` arrays.
///
/// Follows the same incremental parsing pattern as ``ClaudeConversationParser``.
package actor CodexSessionRolloutParser {
    // MARK: Package

    package func parseIncremental(
        sessionID: String,
        rolloutPath: String,
    ) throws -> [ChatHistoryItem] {
        var state = self.sessions[sessionID] ?? RolloutParseState()

        guard FileManager.default.fileExists(atPath: rolloutPath) else {
            throw RolloutParseError.fileNotFound(rolloutPath)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: rolloutPath)
        let currentFileSize = (attributes[.size] as? UInt64) ?? 0

        if currentFileSize < state.lastFileSize {
            state.lastFileOffset = 0
            state.lastFileSize = 0
            state.chatItems = []
        }

        let tailThreshold: UInt64 = 10 * 1024 * 1024
        if state.lastFileOffset == 0, currentFileSize > tailThreshold {
            let tailSize: UInt64 = 1 * 1024 * 1024
            state.lastFileOffset = currentFileSize - tailSize
        }

        let fileURL = URL(fileURLWithPath: rolloutPath)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        handle.seek(toFileOffset: state.lastFileOffset)
        let data = handle.readDataToEndOfFile()

        state.lastFileSize = state.lastFileOffset + UInt64(data.count)

        guard !data.isEmpty else {
            self.sessions[sessionID] = state
            return []
        }

        // Use lossy UTF-8 decoding so a mid-sequence tail offset never
        // produces nil. The first (potentially garbled) line is already
        // skipped by the dropFirst() logic below when in tail mode.
        // swiftlint:disable:next optional_data_string_conversion
        let content = String(decoding: data, as: UTF8.self)

        let allLines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let lines: [Substring] = if state.lastFileOffset > 0, state.chatItems.isEmpty, currentFileSize > tailThreshold {
            Array(allLines.dropFirst())
        } else {
            Array(allLines)
        }

        // Advance offset only past complete lines (those terminated by '\n').
        if content.hasSuffix("\n") {
            state.lastFileOffset += UInt64(data.count)
        } else if let lastNewline = content.lastIndex(of: "\n") {
            let bytesToLastNewline = content[content.startIndex ... lastNewline].utf8.count
            state.lastFileOffset += UInt64(bytesToLastNewline)
        }

        var newItems: [ChatHistoryItem] = []
        let baseIndex = state.chatItems.count

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let lineData = trimmed.data(using: .utf8) else { continue }

            do {
                let item = try JSONDecoder().decode(CodexThreadItem.self, from: lineData)
                let parsed = Self.convertItem(item, itemIndex: baseIndex + lineIndex)
                newItems.append(contentsOf: parsed)
            } catch {
                continue
            }
        }

        state.chatItems.append(contentsOf: newItems)
        self.sessions[sessionID] = state

        return newItems
    }

    package func chatItems(for sessionID: String) -> [ChatHistoryItem] {
        self.sessions[sessionID]?.chatItems ?? []
    }

    package func reset(sessionID: String) {
        self.sessions.removeValue(forKey: sessionID)
    }

    // MARK: Private

    private var sessions: [String: RolloutParseState] = [:]

    private static func convertItem(
        _ item: CodexThreadItem,
        itemIndex: Int,
    ) -> [ChatHistoryItem] {
        let id = item.itemID ?? "rollout-\(itemIndex)"
        let timestamp = Date()

        switch item.type {
        case .userMessage:
            return self.makeTextItem(id: id, timestamp: timestamp, type: .user, text: item.text)
        case .agentMessage:
            return self.makeTextItem(id: id, timestamp: timestamp, type: .assistant, text: item.text)
        case .reasoning:
            return self.makeTextItem(id: id, timestamp: timestamp, type: .reasoning, text: item.summaryText)
        case .commandExecution:
            return self.makeCommandItem(id: id, timestamp: timestamp, item: item)
        case .fileChange:
            return self.makeFileChangeItem(id: id, timestamp: timestamp, item: item)
        case .mcpToolCall:
            return self.makeMCPItem(id: id, timestamp: timestamp, item: item)
        case .collabToolCall:
            let item = ChatHistoryItem(
                id: id, timestamp: timestamp, type: .toolCall,
                content: "subagent: \(item.taskID ?? "unknown")",
            )
            return [item]
        case .webSearch,
             .imageView,
             .enteredReviewMode,
             .compacted:
            return []
        }
    }

    private static func makeTextItem(
        id: String, timestamp: Date, type: ChatItemType, text: String?,
    ) -> [ChatHistoryItem] {
        guard let text, !text.isEmpty else { return [] }
        return [ChatHistoryItem(id: id, timestamp: timestamp, type: type, content: text)]
    }

    private static func makeCommandItem(
        id: String, timestamp: Date, item: CodexThreadItem,
    ) -> [ChatHistoryItem] {
        let command = item.command ?? ""
        let exitStr = item.exitCode.map { " (exit \($0))" } ?? ""
        let historyItem = ChatHistoryItem(
            id: id, timestamp: timestamp, type: .toolCall,
            content: "exec: \(command)\(exitStr)",
            providerSpecific: self.encodeProviderSpecific(item),
        )
        return [historyItem]
    }

    private static func makeFileChangeItem(
        id: String, timestamp: Date, item: CodexThreadItem,
    ) -> [ChatHistoryItem] {
        let path = item.path ?? ""
        let kind = item.kind ?? "modify"
        let historyItem = ChatHistoryItem(
            id: id, timestamp: timestamp, type: .toolCall,
            content: "\(kind): \(path)",
            providerSpecific: self.encodeProviderSpecific(item),
        )
        return [historyItem]
    }

    private static func makeMCPItem(
        id: String, timestamp: Date, item: CodexThreadItem,
    ) -> [ChatHistoryItem] {
        let tool = item.tool ?? "unknown"
        let server = item.server ?? ""
        let historyItem = ChatHistoryItem(
            id: id, timestamp: timestamp, type: .toolCall,
            content: "mcp(\(server)): \(tool)",
            providerSpecific: self.encodeProviderSpecific(item),
        )
        return [historyItem]
    }

    private static func encodeProviderSpecific(_ item: CodexThreadItem) -> JSONValue? {
        guard let data = try? JSONEncoder().encode(item),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            return nil
        }
        return value
    }
}
