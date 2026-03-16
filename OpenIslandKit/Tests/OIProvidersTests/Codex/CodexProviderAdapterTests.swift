import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - CodexProviderAdapterTests

@Suite(.tags(.codex))
struct CodexProviderAdapterTests {
    @Test
    func `conforms to ProviderAdapter`() {
        let adapter = CodexProviderAdapter(binaryPath: "nonexistent-codex-binary")
        let pa: any ProviderAdapter = adapter
        #expect(pa.providerID == .codex)
    }

    @Test
    func `has correct provider metadata`() {
        let adapter = CodexProviderAdapter(binaryPath: "nonexistent-codex-binary")
        #expect(adapter.providerID == .codex)
        #expect(adapter.transportType == .jsonRPC)
        #expect(adapter.metadata.displayName == "Codex")
    }

    @Test
    func `can register with ProviderRegistry`() async {
        let registry = ProviderRegistry()
        let adapter = CodexProviderAdapter(binaryPath: "nonexistent-codex-binary")
        await registry.register(adapter)
        let found = await registry.adapter(for: .codex)
        #expect(found != nil)
        #expect(found?.providerID == .codex)
    }

    @Test
    func `events returns finished stream when not started`() async {
        let adapter = CodexProviderAdapter(binaryPath: "nonexistent-codex-binary")
        let stream = adapter.events()
        var count = 0
        for await _ in stream {
            count += 1
        }
        #expect(count == 0)
    }

    @Test
    func `isSessionAlive returns false when not started`() {
        let adapter = CodexProviderAdapter(binaryPath: "nonexistent-codex-binary")
        #expect(!adapter.isSessionAlive("any-session-id"))
    }
}
