import Darwin
package import Foundation

// MARK: - GeminiHookSocketServer

/// Composes ``HookSocketBridge`` with Gemini-specific event identification.
///
/// `BeforeTool` is the permission interception point — the connection is held
/// open so the app can respond with allow/deny before the tool executes.
package final class GeminiHookSocketServer: Sendable {
    // MARK: Lifecycle

    package init(socketPath: String = "/tmp/open-island-gemini.sock") {
        self.bridge = HookSocketBridge(
            socketPath: socketPath,
            queueLabel: "open-island.gemini-hook-socket",
        )
    }

    // MARK: Package

    package static let allHookEventTypes: [String] = [
        "SessionStart", "SessionEnd",
        "BeforeAgent", "AfterAgent",
        "BeforeModel", "AfterModel",
        "BeforeToolSelection",
        "BeforeTool", "AfterTool",
        "PreCompress",
        "Notification",
    ]

    package var socketPath: String {
        self.bridge.socketPath
    }

    package var isRunning: Bool {
        self.bridge.isRunning
    }

    package func start() throws(SocketServerError) -> AsyncStream<Data> {
        try self.bridge.start(delegate: GeminiBridgeDelegate())
    }

    package func stop() {
        self.bridge.stop()
    }

    @discardableResult
    package func respondToPermission(requestID: String, data: Data) -> Bool {
        self.bridge.respondToPermission(requestID: requestID, data: data)
    }

    package func registerPermissionConnection(_ connection: consuming PermissionConnection) {
        self.bridge.registerPermissionConnection(connection)
    }

    // MARK: Private

    private let bridge: HookSocketBridge
}

// MARK: - GeminiBridgeDelegate

private struct GeminiBridgeDelegate: HookSocketBridgeDelegate {
    // MARK: Internal

    func isPermissionRequest(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(HookEventEnvelope.self, from: data) else {
            return false
        }
        return envelope.hookEventName == "BeforeTool"
    }

    func extractRequestID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let sessionID = json["session_id"] as? String,
           let toolName = json["tool_name"] as? String {
            let timestamp = json["timestamp"] as? String ?? "unknown"
            return "\(sessionID):\(toolName):\(timestamp)"
        }
        return nil
    }

    // MARK: Private

    private struct HookEventEnvelope: Decodable {
        // MARK: Internal

        let hookEventName: String

        // MARK: Private

        private enum CodingKeys: String, CodingKey {
            case hookEventName = "hook_event_name"
        }
    }
}
