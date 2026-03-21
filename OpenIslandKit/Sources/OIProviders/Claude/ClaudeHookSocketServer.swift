import Darwin

// @preconcurrency: DispatchSource, DispatchQueue predate Sendable annotations
@preconcurrency import Dispatch
package import Foundation
import Synchronization

// MARK: - ClaudeHookSocketServer

/// GCD-based Unix domain socket server that receives events from Claude Code hook scripts.
///
/// Composes the shared ``HookSocketBridge`` for socket lifecycle management and adds
/// Claude-specific event identification logic via ``ClaudeBridgeDelegate``.
///
/// Events are bridged from GCD callbacks to Swift concurrency via
/// `AsyncStream.makeStream()` with `.bufferingOldest(128)`.
package final class ClaudeHookSocketServer: Sendable {
    // MARK: Lifecycle

    package init(socketPath: String = "/tmp/open-island-claude.sock") {
        self.bridge = HookSocketBridge(
            socketPath: socketPath,
            queueLabel: "open-island.claude-hook-socket",
        )
    }

    // MARK: Package

    package var socketPath: String {
        self.bridge.socketPath
    }

    package var isRunning: Bool {
        self.bridge.isRunning
    }

    /// Start listening for connections.
    ///
    /// Returns an `AsyncStream<Data>` of raw JSON payloads received from hook scripts.
    /// The server emits raw `Data` — event parsing is handled downstream (Task 3.2).
    package func start() throws(SocketServerError) -> AsyncStream<Data> {
        try self.bridge.start(delegate: ClaudeBridgeDelegate())
    }

    package func stop() {
        self.bridge.stop()
    }

    /// Respond to a pending permission request.
    ///
    /// Finds the held-open connection for the given request ID, writes the
    /// JSON response data, and closes the connection.
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

// MARK: - ClaudeBridgeDelegate

/// Claude-specific delegate for the shared ``HookSocketBridge``.
///
/// Identifies `PermissionRequest` events and extracts `tool_use_id` as the request ID.
private struct ClaudeBridgeDelegate: HookSocketBridgeDelegate {
    // MARK: Internal

    func isPermissionRequest(_ data: Data) -> Bool {
        guard let envelope = try? JSONDecoder().decode(HookEventEnvelope.self, from: data) else {
            return false
        }
        return envelope.hookEventName == "PermissionRequest"
    }

    func extractRequestID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["tool_use_id"] as? String
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
