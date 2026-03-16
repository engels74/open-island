package import Foundation
package import OICore

// MARK: - GeminiConversationParser

/// Parses Gemini CLI session JSON files from `~/.gemini/tmp/<project_hash>/chats/`
/// into ``ChatHistoryItem`` arrays.
///
/// Unlike Claude Code's JSONL transcripts, Gemini CLI stores each session as a
/// complete JSON file containing the full conversation history. This parser reads
/// the JSON file and converts messages into normalized chat history items.
package actor GeminiConversationParser {
    // MARK: Package

    /// Parse a Gemini CLI session JSON file into chat history items.
    ///
    /// - Parameter filePath: Absolute path to the session JSON file.
    /// - Returns: Array of ``ChatHistoryItem`` values.
    package func parse(filePath: String) throws -> [ChatHistoryItem] {
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ConversationParseError.fileNotFound(filePath)
        }

        let data: Data
        do {
            data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        } catch {
            throw ConversationParseError.readFailed(filePath)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConversationParseError.readFailed(filePath)
        }

        return Self.parseSessionJSON(json)
    }

    /// List available session files in a Gemini project's chat directory.
    ///
    /// - Parameter projectChatDir: Path to `~/.gemini/tmp/<project_hash>/chats/`.
    /// - Returns: Array of file paths to session JSON files, sorted by modification date.
    package func listSessions(projectChatDir: String) throws -> [String] {
        let dirURL = URL(fileURLWithPath: projectChatDir)
        guard FileManager.default.fileExists(atPath: projectChatDir) else {
            throw ConversationParseError.fileNotFound(projectChatDir)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles],
        )

        return contents
            .filter { $0.pathExtension == "json" }
            .sorted { lhs, rhs in
                let dateA = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let dateB = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return dateA > dateB
            }
            .map(\.path)
    }

    // MARK: Private

    /// Parse the top-level session JSON into chat history items.
    ///
    /// Expected structure:
    /// ```json
    /// {
    ///   "session_id": "...",
    ///   "messages": [
    ///     { "role": "user", "content": "...", "timestamp": "..." },
    ///     { "role": "model", "parts": [...], "timestamp": "..." }
    ///   ]
    /// }
    /// ```
    private static func parseSessionJSON(_ json: [String: Any]) -> [ChatHistoryItem] {
        guard let messages = json["messages"] as? [[String: Any]] else {
            return []
        }

        var items: [ChatHistoryItem] = []

        for (index, message) in messages.enumerated() {
            let role = message["role"] as? String ?? ""
            let timestamp = self.parseTimestamp(message["timestamp"])
            let messageID = message["id"] as? String ?? "msg-\(index)"

            switch role {
            case "user":
                let content = self.extractContent(from: message)
                if !content.isEmpty {
                    items.append(ChatHistoryItem(
                        id: messageID,
                        timestamp: timestamp,
                        type: .user,
                        content: content,
                    ))
                }

            case "model":
                let parsed = self.parseModelMessage(message, id: messageID, timestamp: timestamp)
                items.append(contentsOf: parsed)

            default:
                break
            }
        }

        return items
    }

    /// Parse a model (assistant) message, which may contain text parts and tool calls.
    private static func parseModelMessage(
        _ message: [String: Any],
        id: String,
        timestamp: Date,
    ) -> [ChatHistoryItem] {
        var items: [ChatHistoryItem] = []

        // Gemini uses "parts" array for structured content
        if let parts = message["parts"] as? [[String: Any]] {
            var textParts: [String] = []
            var toolCallIndex = 0

            for part in parts {
                if let text = part["text"] as? String, !text.isEmpty {
                    textParts.append(text)
                } else if let functionCall = part["functionCall"] as? [String: Any] {
                    let toolName = functionCall["name"] as? String ?? "unknown"
                    let argsDesc = self.describeArgs(functionCall["args"])
                    items.append(ChatHistoryItem(
                        id: "\(id)-tool-\(toolCallIndex)",
                        timestamp: timestamp,
                        type: .toolCall,
                        content: "\(toolName): \(argsDesc)",
                    ))
                    toolCallIndex += 1
                } else if let thought = part["thought"] as? String, !thought.isEmpty {
                    items.append(ChatHistoryItem(
                        id: "\(id)-thinking-\(toolCallIndex)",
                        timestamp: timestamp,
                        type: .thinking,
                        content: thought,
                    ))
                }
            }

            if !textParts.isEmpty {
                items.insert(
                    ChatHistoryItem(
                        id: id,
                        timestamp: timestamp,
                        type: .assistant,
                        content: textParts.joined(separator: "\n"),
                    ),
                    at: 0,
                )
            }
        } else {
            // Fallback: simple content string
            let content = self.extractContent(from: message)
            if !content.isEmpty {
                items.append(ChatHistoryItem(
                    id: id,
                    timestamp: timestamp,
                    type: .assistant,
                    content: content,
                ))
            }
        }

        return items
    }

    /// Extract plain text content from a message.
    private static func extractContent(from message: [String: Any]) -> String {
        // Direct content field
        if let content = message["content"] as? String {
            return content
        }
        // Parts array with text
        if let parts = message["parts"] as? [[String: Any]] {
            return parts
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
        }
        return ""
    }

    private static func parseTimestamp(_ value: Any?) -> Date {
        guard let str = value as? String else { return Date() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: str) { return date }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: str) ?? Date()
    }

    /// Create a brief description of function call arguments.
    private static func describeArgs(_ args: Any?) -> String {
        guard let dict = args as? [String: Any] else { return "" }
        if let command = dict["command"] as? String {
            return String(command.prefix(100))
        }
        if let path = dict["path"] as? String {
            return path
        }
        return dict.keys.sorted().joined(separator: ", ")
    }
}
