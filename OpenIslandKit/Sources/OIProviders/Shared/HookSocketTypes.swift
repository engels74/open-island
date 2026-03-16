// @preconcurrency: DispatchSource, DispatchQueue predate Sendable annotations
@preconcurrency import Dispatch
import Foundation
import Synchronization

// MARK: - PermissionsState

/// Mutable state for tracking pending permission connections.
struct PermissionsState: Sendable {
    /// Pending permission connections keyed by request ID.
    /// Values are boxed to allow `~Copyable` PermissionConnection in a dictionary.
    var pending: [String: PermissionConnectionBox] = [:]

    mutating func insert(_ connection: consuming PermissionConnection, forID id: String) {
        self.pending[id] = PermissionConnectionBox(connection: connection)
    }

    mutating func remove(forID id: String) -> PermissionConnection? {
        self.pending.removeValue(forKey: id)?.take()
    }

    /// Remove all expired connections.
    mutating func removeExpired() {
        let expiredKeys = self.pending.keys.filter { self.pending[$0]?.isExpired == true }
        for key in expiredKeys {
            _ = self.pending.removeValue(forKey: key)
        }
    }
}

// MARK: - PermissionConnectionBox

/// Sendable box for `~Copyable` `PermissionConnection` to allow storage in a dictionary.
final class PermissionConnectionBox: Sendable {
    // MARK: Lifecycle

    init(connection: consuming PermissionConnection) {
        self._connection = Mutex(connection)
    }

    deinit {
        // If the connection was never taken, Mutex's value deinit
        // will run PermissionConnection's deinit, closing the fd.
    }

    // MARK: Internal

    var isExpired: Bool {
        self._connection.withLock { $0?.isExpired ?? true }
    }

    /// Take ownership of the connection, leaving nil behind.
    func take() -> PermissionConnection? {
        self._connection.withLock { connection in
            guard let conn = connection.take() else { return nil }
            return conn
        }
    }

    // MARK: Private

    private let _connection: Mutex<PermissionConnection?>
}

// MARK: - SocketServerError

/// Errors that can occur when starting the socket server.
package enum SocketServerError: Error, Sendable {
    case socketCreationFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case listenFailed(errno: Int32)
    case pathTooLong(String)
    case alreadyRunning
}
