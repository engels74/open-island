import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - AllProviderIDs

/// Extension providing CaseIterable-like access for parameterized tests.
/// ProviderID doesn't conform to CaseIterable, so we provide the list here.
private let allProviderIDs: [ProviderID] = [.claude, .codex, .geminiCLI, .openCode]

// MARK: - ProviderConformanceTests

struct ProviderConformanceTests {
    @Test(arguments: allProviderIDs)
    func `metadata has non-empty displayName`(provider: ProviderID) {
        let metadata = ProviderMetadata.metadata(for: provider)
        #expect(!metadata.displayName.isEmpty)
    }

    @Test(arguments: allProviderIDs)
    func `metadata has non-empty iconName`(provider: ProviderID) {
        let metadata = ProviderMetadata.metadata(for: provider)
        #expect(!metadata.iconName.isEmpty)
    }

    @Test(arguments: allProviderIDs)
    func `metadata has non-empty accentColorHex`(provider: ProviderID) {
        let metadata = ProviderMetadata.metadata(for: provider)
        #expect(!metadata.accentColorHex.isEmpty)
        #expect(metadata.accentColorHex.hasPrefix("#"))
    }

    @Test(arguments: allProviderIDs)
    func `metadata has non-empty cliBinaryNames`(provider: ProviderID) {
        let metadata = ProviderMetadata.metadata(for: provider)
        #expect(!metadata.cliBinaryNames.isEmpty)
    }

    @Test(arguments: allProviderIDs)
    func `metadata has non-empty sessionLogDirectoryPath`(provider: ProviderID) {
        let metadata = ProviderMetadata.metadata(for: provider)
        #expect(!metadata.sessionLogDirectoryPath.isEmpty)
    }

    @Test(arguments: allProviderIDs)
    func `ID round-trips through raw value`(provider: ProviderID) {
        let reconstructed = ProviderID(rawValue: provider.rawValue)
        #expect(reconstructed == provider)
    }

    @Test(arguments: allProviderIDs)
    func `transport types are valid`(provider: ProviderID) {
        let metadata = ProviderMetadata.metadata(for: provider)
        // Each provider's metadata transport type should be valid
        switch metadata.transportType {
        case .hookSocket,
             .jsonRPC,
             .httpSSE:
            break // All valid
        }
    }

    @Test
    func `Claude uses hookSocket transport`() {
        let metadata = ProviderMetadata.metadata(for: .claude)
        #expect(metadata.transportType == .hookSocket)
    }

    @Test
    func `Codex uses jsonRPC transport`() {
        let metadata = ProviderMetadata.metadata(for: .codex)
        #expect(metadata.transportType == .jsonRPC)
    }

    @Test
    func `Gemini CLI uses hookSocket transport`() {
        let metadata = ProviderMetadata.metadata(for: .geminiCLI)
        #expect(metadata.transportType == .hookSocket)
    }

    @Test
    func `OpenCode uses httpSSE transport`() {
        let metadata = ProviderMetadata.metadata(for: .openCode)
        #expect(metadata.transportType == .httpSSE)
    }

    @Test
    func `Registry can register and retrieve all providers`() async {
        let registry = ProviderRegistry()
        let claude = ClaudeProviderAdapter(socketPath: "/tmp/oi-test-conf-claude-\(UUID().uuidString.prefix(8)).sock")
        let codex = CodexProviderAdapter(binaryPath: "nonexistent-codex-binary")
        let gemini = GeminiCLIProviderAdapter(socketPath: "/tmp/oi-test-conf-gemini-\(UUID().uuidString.prefix(8)).sock")
        let opencode = OpenCodeProviderAdapter(configuredPort: 99999)

        await registry.register(claude)
        await registry.register(codex)
        await registry.register(gemini)
        await registry.register(opencode)

        let providers = await registry.registeredProviders
        #expect(providers.count == 4)
        #expect(await registry.adapter(for: .claude) != nil)
        #expect(await registry.adapter(for: .codex) != nil)
        #expect(await registry.adapter(for: .geminiCLI) != nil)
        #expect(await registry.adapter(for: .openCode) != nil)
    }

    @Test
    func `Registry replaces adapter on duplicate registration`() async {
        let registry = ProviderRegistry()
        let adapter1 = CodexProviderAdapter(binaryPath: "binary-1")
        let adapter2 = CodexProviderAdapter(binaryPath: "binary-2")

        await registry.register(adapter1)
        await registry.register(adapter2)

        let providers = await registry.registeredProviders
        // Should still be 1, not 2 — the second registration replaces the first
        #expect(providers.count == 1)
    }

    @Test
    func `All adapters return finished stream when not started`() async {
        let adapters: [any ProviderAdapter] = [
            ClaudeProviderAdapter(socketPath: "/tmp/oi-test-conf-stream-\(UUID().uuidString.prefix(8)).sock"),
            CodexProviderAdapter(binaryPath: "nonexistent"),
            GeminiCLIProviderAdapter(socketPath: "/tmp/oi-test-conf-stream-\(UUID().uuidString.prefix(8)).sock"),
            OpenCodeProviderAdapter(configuredPort: 99999),
        ]

        for adapter in adapters {
            let stream = adapter.events()
            var count = 0
            for await _ in stream {
                count += 1
            }
            #expect(count == 0, "Adapter \(adapter.providerID) should return finished stream when not started")
        }
    }
}
