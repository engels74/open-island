// @preconcurrency: DispatchSource, DispatchQueue predate Sendable annotations
@preconcurrency import Dispatch
import Foundation
import Synchronization

// MARK: - PermissionsState

struct PermissionsState: Sendable {
    /// Boxed because `~Copyable` PermissionConnection can't be stored directly in a dictionary.
    var pending: [String: PermissionConnectionBox] = [:]

    mutating func insert(_ connection: consuming PermissionConnection, forID id: String) {
        self.pending[id] = PermissionConnectionBox(connection: connection)
    }

    mutating func remove(forID id: String) -> PermissionConnection? {
        self.pending.removeValue(forKey: id)?.take()
    }

    mutating func removeExpired() {
        let expiredKeys = self.pending.keys.filter { self.pending[$0]?.isExpired == true }
        for key in expiredKeys {
            _ = self.pending.removeValue(forKey: key)
        }
    }
}

// MARK: - PermissionConnectionBox

/// Sendable box for `~Copyable` PermissionConnection to allow dictionary storage.
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

package enum SocketServerError: Error, Sendable {
    case socketCreationFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case listenFailed(errno: Int32)
    case pathTooLong(String)
    case alreadyRunning
}
