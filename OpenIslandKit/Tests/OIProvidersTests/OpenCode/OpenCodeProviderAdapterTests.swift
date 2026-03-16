import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - OpenCodeProviderAdapterTests

@Suite(.tags(.opencode))
struct OpenCodeProviderAdapterTests {
    @Test
    func `conforms to ProviderAdapter`() {
        let adapter = OpenCodeProviderAdapter(configuredPort: 99999)
        let pa: any ProviderAdapter = adapter
        #expect(pa.providerID == .openCode)
    }

    @Test
    func `has correct provider metadata`() {
        let adapter = OpenCodeProviderAdapter(configuredPort: 99999)
        #expect(adapter.providerID == .openCode)
        #expect(adapter.transportType == .httpSSE)
        #expect(adapter.metadata.displayName == "OpenCode")
    }

    @Test
    func `can register with ProviderRegistry`() async {
        let registry = ProviderRegistry()
        let adapter = OpenCodeProviderAdapter(configuredPort: 99999)
        await registry.register(adapter)
        let found = await registry.adapter(for: .openCode)
        #expect(found != nil)
        #expect(found?.providerID == .openCode)
    }

    @Test
    func `events returns finished stream when not started`() async {
        let adapter = OpenCodeProviderAdapter(configuredPort: 99999)
        let stream = adapter.events()
        var count = 0
        for await _ in stream {
            count += 1
        }
        #expect(count == 0)
    }

    @Test
    func `isSessionAlive returns false when not started`() {
        let adapter = OpenCodeProviderAdapter(configuredPort: 99999)
        #expect(!adapter.isSessionAlive("any-session-id"))
    }
}
