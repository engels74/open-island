import Darwin
package import Foundation

// MARK: - GeminiHookSocketServer

/// GCD-based Unix domain socket server that receives events from Gemini CLI hook scripts.
///
/// Composes the shared ``HookSocketBridge`` for socket lifecycle management and adds
/// Gemini-specific event identification logic via ``GeminiBridgeDelegate``.
///
/// Gemini CLI's `BeforeTool` hook is the permission interception point — the connection
/// is held open so the app can respond with allow/deny before the tool executes.
package final class GeminiHookSocketServer: Sendable {
    // MARK: Lifecycle

    package init(socketPath: String = "/tmp/open-island-gemini.sock") {
        self.bridge = HookSocketBridge(
            socketPath: socketPath,
            queueLabel: "open-island.gemini-hook-socket",
        )
    }

    // MARK: Package

    /// All Gemini CLI hook event types.
    package static let allHookEventTypes: [String] = [
        "SessionStart", "SessionEnd",
        "BeforeAgent", "AfterAgent",
        "BeforeModel", "AfterModel",
        "BeforeToolSelection",
        "BeforeTool", "AfterTool",
        "PreCompress",
        "Notification",
    ]

    /// The Unix domain socket path this server listens on.
    package var socketPath: String {
        self.bridge.socketPath
    }

    /// Whether the server is currently running.
    package var isRunning: Bool {
        self.bridge.isRunning
    }

    /// Start listening for connections.
    ///
    /// Returns an `AsyncStream<Data>` of raw JSON payloads received from hook scripts.
    package func start() throws(SocketServerError) -> AsyncStream<Data> {
        try self.bridge.start(delegate: GeminiBridgeDelegate())
    }

    /// Stop the server and clean up resources.
    package func stop() {
        self.bridge.stop()
    }

    /// Respond to a pending permission request (BeforeTool event).
    ///
    /// - Parameters:
    ///   - requestID: The permission request ID to respond to.
    ///   - data: JSON response data to send back to the hook script.
    /// - Returns: `true` if the response was sent, `false` if no pending connection was found.
    @discardableResult
    package func respondToPermission(requestID: String, data: Data) -> Bool {
        self.bridge.respondToPermission(requestID: requestID, data: data)
    }

    /// Register a held-open permission connection.
    package func registerPermissionConnection(_ connection: consuming PermissionConnection) {
        self.bridge.registerPermissionConnection(connection)
    }

    // MARK: Private

    private let bridge: HookSocketBridge
}

// MARK: - GeminiBridgeDelegate

/// Gemini-specific delegate for the shared ``HookSocketBridge``.
///
/// Identifies `BeforeTool` events as the permission interception point and extracts
/// a unique request ID from the event data. Unlike Claude's `PermissionRequest`,
/// Gemini uses `BeforeTool` — the hook can deny execution or rewrite arguments
/// before the tool runs.
private struct GeminiBridgeDelegate: HookSocketBridgeDelegate {
    // MARK: Internal

    func isPermissionRequest(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(HookEventEnvelope.self, from: data) else {
            return false
        }
        // BeforeTool is the permission interception point in Gemini CLI
        return envelope.hookEventName == "BeforeTool"
    }

    func extractRequestID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Gemini CLI uses session_id + tool_name + timestamp to identify tool calls.
        // Construct a composite ID from available fields.
        if let sessionID = json["session_id"] as? String,
           let toolName = json["tool_name"] as? String {
            let timestamp = json["timestamp"] as? String ?? "unknown"
            return "\(sessionID):\(toolName):\(timestamp)"
        }
        return nil
    }

    // MARK: Private

    /// Lightweight envelope for extracting `hook_event_name` without full event decoding.
    private struct HookEventEnvelope: Decodable {
        // MARK: Internal

        let hookEventName: String

        // MARK: Private

        private enum CodingKeys: String, CodingKey {
            case hookEventName = "hook_event_name"
        }
    }
}
