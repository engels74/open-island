package import Foundation
package import OICore

// MARK: - SessionParseState

/// Tracks incremental parsing state for a single Claude Code session transcript.
package struct SessionParseState: Sendable {
    /// Byte offset of the last read position in the JSONL file.
    package var lastFileOffset: UInt64 = 0
    /// File size at last read, used for truncation detection.
    package var lastFileSize: UInt64 = 0
    /// Accumulated chat history items for this session.
    package var chatItems: [ChatHistoryItem] = []
}

// MARK: - SessionIndexEntry

/// An entry from Claude Code's `sessions-index.json` file.
package struct SessionIndexEntry: Sendable, Codable {
    // MARK: Package

    package let sessionID: String
    package let projectName: String
    package let summary: String?
    package let messageCount: Int?
    package let gitBranch: String?
    package let lastActiveAt: Date?

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case projectName = "project_name"
        case summary
        case messageCount = "message_count"
        case gitBranch = "git_branch"
        case lastActiveAt = "last_active_at"
    }
}

// MARK: - ConversationParseError

/// Errors that can occur during conversation parsing.
package enum ConversationParseError: Error, Sendable {
    case fileNotFound(String)
    case readFailed(String)
}

// MARK: - ClaudeConversationParser

/// Incrementally parses Claude Code JSONL session transcript files into
/// ``ChatHistoryItem`` arrays.
///
/// Each Claude Code session writes a `.jsonl` file at
/// `~/.claude/projects/<project-name>/<session-uuid>.jsonl`.
/// This actor tracks file offsets per session to only parse new lines
/// on each invocation, supporting efficient polling.
package actor ClaudeConversationParser {
    // MARK: Package

    /// Parse new lines from a session transcript file since the last read.
    ///
    /// - Parameters:
    ///   - sessionID: The unique session identifier.
    ///   - transcriptPath: Absolute path to the `.jsonl` transcript file.
    /// - Returns: Only the newly parsed ``ChatHistoryItem`` values since the last call.
    package func parseIncremental(
        sessionID: String,
        transcriptPath: String,
    ) throws -> [ChatHistoryItem] {
        var state = self.sessions[sessionID] ?? SessionParseState()

        let fileURL = URL(fileURLWithPath: transcriptPath)
        guard FileManager.default.fileExists(atPath: transcriptPath) else {
            throw ConversationParseError.fileNotFound(transcriptPath)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: transcriptPath)
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
            let tailSize: UInt64 = 1 * 1024 * 1024 // Read last 1MB
            state.lastFileOffset = currentFileSize - tailSize
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        handle.seek(toFileOffset: state.lastFileOffset)
        let data = handle.readDataToEndOfFile()

        state.lastFileSize = currentFileSize

        guard !data.isEmpty else {
            self.sessions[sessionID] = state
            return []
        }

        // If we seeked to a mid-file position for tail-based reading,
        // skip the first partial line (unless we're at offset 0).
        let lines: [Substring]
        if let content = String(data: data, encoding: .utf8) {
            let allLines = content.split(separator: "\n", omittingEmptySubsequences: false)
            if state.lastFileOffset > 0, state.chatItems.isEmpty, currentFileSize > tailThreshold {
                // Skip first potentially partial line when doing tail-based read
                lines = Array(allLines.dropFirst())
            } else {
                lines = Array(allLines)
            }
        } else {
            self.sessions[sessionID] = state
            return []
        }

        state.lastFileOffset = currentFileSize

        var newItems: [ChatHistoryItem] = []
        let baseIndex = state.chatItems.count

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else {
                // Skip malformed JSONL lines gracefully
                continue
            }

            let parsed = Self.parseLine(json, itemIndex: baseIndex + lineIndex)
            newItems.append(contentsOf: parsed)
        }

        state.chatItems.append(contentsOf: newItems)
        self.sessions[sessionID] = state

        return newItems
    }

    /// Parse the `sessions-index.json` file from a Claude Code project directory.
    ///
    /// - Parameter projectPath: Path to the Claude project directory
    ///   (e.g. `~/.claude/projects/my-project`).
    /// - Returns: Array of session index entries.
    package func parseSessionsIndex(projectPath: String) throws -> [SessionIndexEntry] {
        let indexPath = (projectPath as NSString).appendingPathComponent("sessions-index.json")

        guard FileManager.default.fileExists(atPath: indexPath) else {
            throw ConversationParseError.fileNotFound(indexPath)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: indexPath))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SessionIndexEntry].self, from: data)
    }

    /// Reset chat history for a session (e.g. when `/clear` is detected).
    package func handleClear(sessionID: String) {
        self.sessions[sessionID]?.chatItems = []
    }

    /// Return the current accumulated chat items for a session.
    package func chatItems(for sessionID: String) -> [ChatHistoryItem] {
        self.sessions[sessionID]?.chatItems ?? []
    }

    // MARK: Private

    /// Per-session parsing state.
    private var sessions: [String: SessionParseState] = [:]

    private static func parseTimestamp(_ value: Any?) -> Date {
        guard let str = value as? String else { return Date() }
        // Try with fractional seconds first, then without.
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: str) { return date }

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: str) ?? Date()
    }

    /// Parse a single JSONL line into zero or more ``ChatHistoryItem`` values.
    private static func parseLine(_ json: [String: Any], itemIndex: Int) -> [ChatHistoryItem] {
        guard let type = json["type"] as? String else { return [] }

        let timestamp = self.parseTimestamp(json["timestamp"])
        let uuid = (json["uuid"] as? String) ?? "line-\(itemIndex)"

        switch type {
        case "human":
            return self.parseHumanLine(json, uuid: uuid, timestamp: timestamp)
        case "assistant":
            return self.parseAssistantLine(json, uuid: uuid, timestamp: timestamp)
        case "tool_result",
             "summary":
            // tool_result tracked by ToolTracker; summary is internal
            return []
        default:
            return []
        }
    }

    private static func parseHumanLine(
        _ json: [String: Any],
        uuid: String,
        timestamp: Date,
    ) -> [ChatHistoryItem] {
        let text = self.extractTextContent(from: json)
        guard !text.isEmpty else { return [] }

        return [
            ChatHistoryItem(
                id: uuid,
                timestamp: timestamp,
                type: .user,
                content: text,
            ),
        ]
    }

    private static func parseAssistantLine(
        _ json: [String: Any],
        uuid: String,
        timestamp: Date,
    ) -> [ChatHistoryItem] {
        guard let message = json["message"] as? [String: Any],
              let contentArray = message["content"] as? [[String: Any]]
        else {
            return []
        }

        var items: [ChatHistoryItem] = []
        var textParts: [String] = []
        var toolCallIndex = 0
        var thinkingIndex = 0

        for block in contentArray {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    textParts.append(text)
                }
            case "tool_use":
                let toolName = (block["name"] as? String) ?? "unknown"
                let toolID = (block["id"] as? String) ?? "tu-\(toolCallIndex)"
                let inputDesc = self.describeToolInput(block["input"])
                items.append(ChatHistoryItem(
                    id: "\(uuid)-tool-\(toolCallIndex)",
                    timestamp: timestamp,
                    type: .toolCall,
                    content: "\(toolName): \(inputDesc)",
                    providerSpecific: self.encodeToolUseBlock(block),
                ))
                toolCallIndex += 1
            case "thinking":
                if let text = block["thinking"] as? String, !text.isEmpty {
                    items.append(ChatHistoryItem(
                        id: "\(uuid)-thinking-\(thinkingIndex)",
                        timestamp: timestamp,
                        type: .thinking,
                        content: text,
                    ))
                    thinkingIndex += 1
                }
            default:
                break
            }
        }

        // Emit the concatenated text blocks as a single assistant message.
        if !textParts.isEmpty {
            let combined = textParts.joined(separator: "\n")
            items.insert(
                ChatHistoryItem(
                    id: uuid,
                    timestamp: timestamp,
                    type: .assistant,
                    content: combined,
                ),
                at: 0,
            )
        }

        return items
    }

    /// Extract concatenated text from `message.content[].text` blocks.
    private static func extractTextContent(from json: [String: Any]) -> String {
        guard let message = json["message"] as? [String: Any],
              let contentArray = message["content"] as? [[String: Any]]
        else {
            return ""
        }

        return contentArray
            .compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }
            .joined(separator: "\n")
    }

    /// Create a brief description of tool input for display.
    private static func describeToolInput(_ input: Any?) -> String {
        guard let dict = input as? [String: Any] else { return "" }
        if let command = dict["command"] as? String {
            return command.prefix(100).description
        }
        if let filePath = dict["file_path"] as? String {
            return filePath
        }
        if let pattern = dict["pattern"] as? String {
            return pattern
        }
        return dict.keys.sorted().joined(separator: ", ")
    }

    /// Encode a tool_use block as ``JSONValue`` for `providerSpecific`.
    private static func encodeToolUseBlock(_ block: [String: Any]) -> JSONValue? {
        guard let data = try? JSONSerialization.data(withJSONObject: block),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            return nil
        }
        return value
    }
}
