// @preconcurrency: DispatchSource, DispatchQueue predate Sendable annotations
@preconcurrency import Dispatch
import Foundation

/// A `~Copyable` wrapper for a held-open client socket connection
/// used during permission request flows.
///
/// When Claude Code sends a `PermissionRequest` hook event, the Python hook script
/// keeps the socket connection open and blocks waiting for a response. This type
/// wraps that held-open connection with a 5-minute timeout.
///
/// Use `consuming func respond(_:)` to write the JSON response and close
/// the connection. Ownership transfer via `consuming` ensures the connection
/// cannot be used after the response is sent.
package struct PermissionConnection: ~Copyable {
    // MARK: Lifecycle

    package init(clientFD: consuming SocketFD, requestID: String) {
        self.clientFD = clientFD
        self.requestID = requestID
        self.createdAt = DispatchTime.now()
    }

    // MARK: Package

    /// The permission request ID this connection is waiting on.
    package let requestID: String

    /// Whether this connection has exceeded the 5-minute timeout.
    package var isExpired: Bool {
        let elapsed = DispatchTime.now().uptimeNanoseconds - self.createdAt.uptimeNanoseconds
        let fiveMinutesNanos: UInt64 = 5 * 60 * 1_000_000_000
        return elapsed > fiveMinutesNanos
    }

    // MARK: Internal

    /// Write a JSON response to the held-open connection and close it.
    ///
    /// Consumes ownership — the connection cannot be used after responding.
    /// The underlying `SocketFD` is closed when its `deinit` fires at the
    /// end of this function (no explicit `close()` needed).
    consuming func respond(_ jsonData: Data) {
        jsonData.withUnsafeBytes { buffer in
            _ = self.clientFD.write(buffer)
        }
        // clientFD's deinit closes the fd when self is consumed
    }

    // MARK: Private

    /// Timeout: 5 minutes from creation.
    private let createdAt: DispatchTime

    private var clientFD: SocketFD
}
