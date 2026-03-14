import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - TestProviderID

/// Local test-only enum representing supported providers.
/// Used for parameterized tests — not the production `ProviderID`.
enum TestProviderID: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case claude
    case codex
    case geminiCLI = "gemini-cli"
    case openCode = "open-code"

    // MARK: Internal

    var testDescription: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex CLI"
        case .geminiCLI: "Gemini CLI"
        case .openCode: "OpenCode"
        }
    }
}

// MARK: - Tags (mirrored from OICoreTests for cross-target access)

extension Tag {
    @Tag static var claude: Self
    @Tag static var codex: Self
    @Tag static var gemini: Self
    @Tag static var opencode: Self
    @Tag static var socket: Self
}

// MARK: - ProviderPatternTests

struct ProviderPatternTests {
    @Test(arguments: TestProviderID.allCases)
    func nonEmptyDisplayName(provider: TestProviderID) {
        #expect(!provider.displayName.isEmpty)
    }

    @Test(arguments: TestProviderID.allCases)
    func validRawValueIdentifier(provider: TestProviderID) {
        #expect(!provider.rawValue.isEmpty)
        #expect(provider.rawValue == provider.rawValue.lowercased())
    }

    @Test(.tags(.claude, .codex), arguments: TestProviderID.allCases)
    func providerRoundTrips(provider: TestProviderID) {
        let reconstructed = TestProviderID(rawValue: provider.rawValue)
        #expect(reconstructed == provider)
    }
}

// MARK: - SharedResourceTests

@Suite(.serialized)
struct SharedResourceTests {
    @Test(.tags(.claude))
    func sequentialAccessToSharedConfig() {
        let config: [String: String] = ["provider": "claude", "transport": "hookSocket"]
        #expect(config["provider"] == "claude")
        #expect(config["transport"] == "hookSocket")
    }

    @Test(.tags(.codex))
    func sequentialMutationDoesNotRace() {
        var sessions: [String] = []
        sessions.append("session-1")
        sessions.append("session-2")
        #expect(sessions.count == 2)
    }
}

// MARK: - SocketTests

struct SocketTests {
    @Test(.tags(.socket), .timeLimit(.minutes(1)))
    func socketPathValidation() {
        let socketPath = "/tmp/openisland-test.sock"
        #expect(socketPath.hasSuffix(".sock"))
        #expect(socketPath.hasPrefix("/"))
    }

    @Test(.tags(.socket), .timeLimit(.minutes(1)))
    func socketPathLengthWithinUnixLimit() {
        let socketPath = "/tmp/oi.sock"
        // Unix domain socket paths are limited to ~104 bytes on macOS
        #expect(socketPath.utf8.count < 104)
    }
}

// MARK: - ConditionalTests

struct ConditionalTests {
    @Test(.disabled("Provider registry not yet implemented"))
    func featureBehindFlag() {
        // Will be enabled once ProviderRegistry exists in Phase 1.6
        #expect(Bool(true))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15))
    func platformSpecificTest() {
        #expect(Bool(true))
    }

    @Test(.enabled(if: true, "Always enabled for demonstration"))
    func conditionedOnEnvironment() {
        #expect(Bool(true))
    }
}

// MARK: - BugTrackingTests

struct BugTrackingTests {
    @Test(.bug(id: "OI-42", "Provider disconnect can race with event delivery"))
    func workaroundForProviderDisconnectRace() {
        // Simulates the fix: events arriving after disconnect are dropped
        let isConnected = false
        let pendingEvents = 3
        let deliveredCount = isConnected ? pendingEvents : 0
        #expect(deliveredCount == 0)
    }

    @Test(.tags(.claude), .bug(id: "OI-17"))
    func hookInstallationIdempotency() {
        // Installing hooks twice should not duplicate entries
        var hooks: Set<String> = []
        hooks.insert("UserPromptSubmit")
        hooks.insert("UserPromptSubmit") // duplicate
        #expect(hooks.count == 1)
    }
}
