package import Foundation
package import OICore

// MARK: - GeminiHeadlessStreamParser

/// Parses JSONL output from `gemini -p "query" --output-format stream-json`
/// into ``ProviderEvent`` values. Alternative to hooks for non-interactive sessions.
package struct GeminiHeadlessStreamParser: Sendable {
    // MARK: Lifecycle

    package init() {}

    // MARK: Package

    package func parse(_ data: Data) -> ProviderEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        guard let eventType = json["type"] as? String else {
            return nil
        }

        let sessionID = json["session_id"] as? String ?? "headless"

        switch eventType {
        case "init":
            let cwd = json["cwd"] as? String ?? ""
            return .sessionStarted(sessionID, cwd: cwd, pid: nil)

        case "message":
            guard let text = json["content"] as? String else { return nil }
            return .modelResponse(sessionID, textDelta: text)

        case "tool_use":
            let toolName = json["tool_name"] as? String ?? "unknown"
            let toolInput = json["tool_input"]
                .flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                .flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
            let toolEvent = ToolEvent(
                id: json["tool_use_id"] as? String ?? "unknown",
                name: toolName,
                input: toolInput,
                startedAt: Date(),
            )
            return .toolStarted(sessionID, toolEvent)

        case "tool_result":
            let toolName = json["tool_name"] as? String ?? "unknown"
            let toolEvent = ToolEvent(
                id: json["tool_use_id"] as? String ?? "unknown",
                name: toolName,
                input: nil,
                startedAt: Date(),
            )
            let resultContent = json["content"] as? String
            let toolResult = ToolResult(
                output: resultContent.map { .string($0) },
                isSuccess: true,
            )
            return .toolCompleted(sessionID, toolEvent, toolResult)

        case "error":
            let message = json["message"] as? String ?? "Unknown error"
            return .notification(sessionID, message: "Error: \(message)")

        case "result":
            if let usage = json["usage_metadata"] as? [String: Any] {
                let total = usage["totalTokenCount"] as? Int
                let prompt = usage["promptTokenCount"] as? Int
                let completion = usage["candidatesTokenCount"] as? Int
                return .tokenUsage(
                    sessionID,
                    promptTokens: prompt,
                    completionTokens: completion,
                    totalTokens: total,
                )
            }
            return .sessionEnded(sessionID)

        default:
            return nil
        }
    }

    package func parseStream(_ data: Data) -> [ProviderEvent] {
        let lines = data.split(separator: UInt8(ascii: "\n"))
        return lines.compactMap { self.parse(Data($0)) }
    }
}
