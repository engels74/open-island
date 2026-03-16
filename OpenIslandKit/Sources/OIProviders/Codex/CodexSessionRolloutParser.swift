import Foundation
package import OICore

// MARK: - RolloutParseState

/// Tracks incremental parsing state for a single Codex session rollout file.
package struct RolloutParseState: Sendable {
    /// Byte offset of the last read position in the JSONL file.
    package var lastFileOffset: UInt64 = 0
    /// File size at last read, used for truncation detection.
    package var lastFileSize: UInt64 = 0
    /// Accumulated chat history items for this session.
    package var chatItems: [ChatHistoryItem] = []
}

// MARK: - RolloutParseError

/// Errors that can occur during rollout file parsing.
package enum RolloutParseError: Error, Sendable {
    case fileNotFound(String)
    case readFailed(String)
}

// MARK: - CodexSessionRolloutParser

/// Incrementally parses Codex session rollout JSONL files into ``ChatHistoryItem`` arrays.
///
/// Codex writes complete conversation history to rollout files at
/// `~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl`.
/// This actor tracks file offsets per session to only parse new lines
/// on each invocation, supporting efficient FSEvents-based polling.
///
/// Follows the same incremental parsing pattern as ``ClaudeConversationParser``.
package actor CodexSessionRolloutParser {
    // MARK: Package

    /// Parse new lines from a rollout file since the last read.
    ///
    /// - Parameters:
    ///   - sessionID: The unique session identifier.
    ///   - rolloutPath: Absolute path to the rollout `.jsonl` file.
    /// - Returns: Only the newly parsed ``ChatHistoryItem`` values since the last call.
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

        // Detect file truncation: if current size is smaller than last known size, reset.
        if currentFileSize < state.lastFileSize {
            state.lastFileOffset = 0
            state.lastFileSize = 0
            state.chatItems = []
        }

        // For large files (>10MB), use tail-based approach if starting fresh.
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

        guard let content = String(data: data, encoding: .utf8) else {
            self.sessions[sessionID] = state
            return []
        }

        let allLines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let lines: [Substring] = if state.lastFileOffset > 0, state.chatItems.isEmpty, currentFileSize > tailThreshold {
            // Skip first potentially partial line when doing tail-based read
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
        // If no newline found at all, don't advance — the entire read is a partial line.

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
                // Skip malformed JSONL lines gracefully
                continue
            }
        }

        state.chatItems.append(contentsOf: newItems)
        self.sessions[sessionID] = state

        return newItems
    }

    /// Return the current accumulated chat items for a session.
    package func chatItems(for sessionID: String) -> [ChatHistoryItem] {
        self.sessions[sessionID]?.chatItems ?? []
    }

    /// Reset chat history for a session.
    package func reset(sessionID: String) {
        self.sessions.removeValue(forKey: sessionID)
    }

    // MARK: Private

    /// Per-session parsing state.
    private var sessions: [String: RolloutParseState] = [:]

    /// Convert a Codex thread item into zero or more ChatHistoryItem values.
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

    /// Encode select fields of a CodexThreadItem as a JSONValue for providerSpecific.
    private static func encodeProviderSpecific(_ item: CodexThreadItem) -> JSONValue? {
        guard let data = try? JSONEncoder().encode(item),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            return nil
        }
        return value
    }
}
