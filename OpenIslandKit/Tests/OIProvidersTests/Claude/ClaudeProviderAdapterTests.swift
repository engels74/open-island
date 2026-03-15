import Darwin
import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - ClaudeProviderAdapterTests

@Suite(.tags(.claude))
struct ClaudeProviderAdapterTests {
    @Test
    func `conforms to ProviderAdapter`() {
        let adapter = ClaudeProviderAdapter(socketPath: uniqueSocketPath())
        let pa: any ProviderAdapter = adapter
        #expect(pa.providerID == .claude)
    }

    @Test
    func `has correct provider metadata`() {
        let adapter = ClaudeProviderAdapter(socketPath: uniqueSocketPath())
        #expect(adapter.providerID == .claude)
        #expect(adapter.transportType == .hookSocket)
        #expect(adapter.metadata.displayName == "Claude Code")
    }

    @Test
    func `can register with ProviderRegistry`() async {
        let registry = ProviderRegistry()
        let adapter = ClaudeProviderAdapter(socketPath: uniqueSocketPath())
        await registry.register(adapter)
        let found = await registry.adapter(for: .claude)
        #expect(found != nil)
        #expect(found?.providerID == .claude)
    }

    @Test
    func `isSessionAlive returns true`() {
        let adapter = ClaudeProviderAdapter(socketPath: uniqueSocketPath())
        #expect(adapter.isSessionAlive("any-session-id"))
    }

    @Test
    func `events returns finished stream when not started`() async {
        let adapter = ClaudeProviderAdapter(socketPath: uniqueSocketPath())
        let stream = adapter.events()
        var count = 0
        for await _ in stream {
            count += 1
        }
        #expect(count == 0)
    }
}

// MARK: - ClaudeProviderAdapterLifecycleTests

@Suite(.tags(.claude, .socket), .serialized)
struct ClaudeProviderAdapterLifecycleTests {
    @Test(.timeLimit(.minutes(1)))
    func `start and stop lifecycle`() async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)

        try await adapter.start()
        #expect(FileManager.default.fileExists(atPath: path))

        await adapter.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test(.timeLimit(.minutes(1)))
    func `double start throws alreadyRunning`() async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)

        try await adapter.start()

        await #expect(throws: ProviderStartupError.self) {
            try await adapter.start()
        }

        await adapter.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func `events stream emits normalized events from socket`() async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)

        try await adapter.start()
        let stream = adapter.events()

        // Allow socket server to be ready for connections
        try await Task.sleep(for: .milliseconds(50))

        // Send a SessionStart event via the socket
        let payload = #"{"session_id":"s1","hook_event_name":"SessionStart","session_type":"startup","cwd":"/tmp"}"# + "\n"
        sendToSocket(path: path, data: Data(payload.utf8))

        // Read one event from the stream
        var receivedEvent: ProviderEvent?
        for await event in stream {
            receivedEvent = event
            break
        }

        await adapter.stop()

        // Verify we got a sessionStarted event
        guard let event = receivedEvent else {
            Issue.record("Expected to receive an event")
            return
        }

        if case let .sessionStarted(sid, cwd, _) = event {
            #expect(sid == "s1")
            #expect(cwd == "/tmp")
        } else {
            Issue.record("Expected .sessionStarted, got \(event)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `respondToPermission throws when no connection`() async throws {
        let path = uniqueSocketPath()
        let adapter = ClaudeProviderAdapter(socketPath: path)

        try await adapter.start()

        let request = PermissionRequest(
            id: "perm-nonexistent",
            toolName: "Bash",
            timestamp: Date(),
        )

        await #expect(throws: PermissionResponseError.self) {
            try await adapter.respondToPermission(request, decision: .allow)
        }

        await adapter.stop()
    }
}

// MARK: - Helpers

/// Generate a unique socket path to avoid test interference.
private func uniqueSocketPath() -> String {
    "/tmp/oi-test-adapter-\(UUID().uuidString.prefix(8)).sock"
}

/// Connect to a Unix domain socket and send data.
private func sendToSocket(path: String, data: Data) {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = path.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
            pathBytes.withUnsafeBufferPointer { src in
                guard let srcBase = src.baseAddress else { return }
                _ = memcpy(dest, srcBase, src.count)
            }
        }
    }

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard connectResult == 0 else {
        Darwin.close(fd)
        return
    }

    data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return }
        _ = Darwin.write(fd, base, buffer.count)
    }

    Darwin.close(fd)
}
