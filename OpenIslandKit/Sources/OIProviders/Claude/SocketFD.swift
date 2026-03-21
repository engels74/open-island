import Darwin

/// A `~Copyable` wrapper around a Unix file descriptor.
///
/// Ensures the fd is closed exactly once — double-close or use-after-close
/// is a compile-time error. Use `borrowing` methods for I/O and
/// `consuming func close()` to explicitly release the resource.
package struct SocketFD: ~Copyable {
    // MARK: Lifecycle

    package init(_ fd: Int32) {
        self.fd = fd
    }

    deinit {
        Darwin.close(fd)
    }

    // MARK: Package

    /// The raw file descriptor value.
    package var rawValue: Int32 {
        self.fd
    }

    // MARK: Internal

    /// - Parameter buffer: Mutable buffer to read into. Must be valid only
    ///   within the calling `withUnsafe*` closure scope — never escape.
    borrowing func read(into buffer: UnsafeMutableRawBufferPointer) -> Int {
        guard let base = buffer.baseAddress else { return -1 }
        return Darwin.read(self.fd, base, buffer.count)
    }

    /// Retries on short writes (e.g. EINTR) to ensure the full buffer is sent.
    ///
    /// - Parameter data: Buffer of bytes to write. Must be valid only
    ///   within the calling `withUnsafe*` closure scope — never escape.
    borrowing func write(_ data: UnsafeRawBufferPointer) -> Int {
        guard let base = data.baseAddress else { return -1 }
        var totalWritten = 0
        while totalWritten < data.count {
            let bytesWritten = Darwin.write(
                self.fd,
                base.advanced(by: totalWritten),
                data.count - totalWritten,
            )
            if bytesWritten < 0 {
                if errno == EINTR { continue }
                return bytesWritten
            }
            totalWritten += bytesWritten
        }
        return totalWritten
    }

    /// Uses `discard self` to suppress `deinit` — cleanup is done here.
    consuming func close() {
        Darwin.close(self.fd)
        discard self
    }

    // MARK: Private

    private let fd: Int32
}
