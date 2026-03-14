import Foundation
@testable import OICore
import Testing

struct ProviderIDTests {
    @Test(arguments: [
        ("claude", ProviderID.claude),
        ("codex", ProviderID.codex),
        ("geminiCLI", ProviderID.geminiCLI),
        ("openCode", ProviderID.openCode),
    ])
    func `Raw value round-trip`(rawValue: String, expected: ProviderID) {
        #expect(expected.rawValue == rawValue)
        #expect(ProviderID(rawValue: rawValue) == expected)
    }

    @Test
    func `Invalid raw value returns nil`() {
        #expect(ProviderID(rawValue: "unknown") == nil)
        #expect(ProviderID(rawValue: "") == nil)
    }

    @Test
    func `Codable round-trip`() throws {
        let original = ProviderID.claude
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderID.self, from: data)
        #expect(decoded == original)
    }

    @Test
    func `Hashable — can be used as dictionary key`() {
        var dict: [ProviderID: String] = [:]
        dict[.claude] = "Claude Code"
        dict[.codex] = "Codex"
        #expect(dict[.claude] == "Claude Code")
        #expect(dict[.codex] == "Codex")
        #expect(dict[.geminiCLI] == nil)
    }

    @Test(arguments: [
        (ProviderID.claude, "Claude Code"),
        (ProviderID.codex, "Codex"),
        (ProviderID.geminiCLI, "Gemini CLI"),
        (ProviderID.openCode, "OpenCode"),
    ])
    func `Metadata lookup returns correct display names`(providerID: ProviderID, expectedName: String) {
        let metadata = ProviderMetadata.metadata(for: providerID)
        #expect(metadata.displayName == expectedName)
    }

    @Test
    func `Metadata transport types`() {
        #expect(ProviderMetadata.metadata(for: .claude).transportType == .hookSocket)
        #expect(ProviderMetadata.metadata(for: .codex).transportType == .jsonRPC)
        #expect(ProviderMetadata.metadata(for: .geminiCLI).transportType == .hookSocket)
        #expect(ProviderMetadata.metadata(for: .openCode).transportType == .httpSSE)
    }

    @Test
    func `Metadata config file formats`() {
        #expect(ProviderMetadata.metadata(for: .claude).configFileFormat == .json)
        #expect(ProviderMetadata.metadata(for: .codex).configFileFormat == .toml)
    }

    @Test
    func `Metadata has non-empty CLI binary names`() {
        let allProviders: [ProviderID] = [.claude, .codex, .geminiCLI, .openCode]
        for provider in allProviders {
            let metadata = ProviderMetadata.metadata(for: provider)
            #expect(!metadata.cliBinaryNames.isEmpty)
        }
    }
}
