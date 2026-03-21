@testable import OICore
import Testing

// MARK: - TagUsageExampleTests

struct TagUsageExampleTests {
    @Test(.tags(.claude))
    func `claude tagged filter correctly`() {
        // Run with: swift test --filter .tags:claude
        #expect(Bool(true))
    }

    @Test(.tags(.socket))
    func `socket tagged transport layer`() {
        // Run with: swift test --filter .tags:socket
        #expect(Bool(true))
    }

    @Test(.tags(.ui))
    func `ui tagged view layer`() {
        #expect(Bool(true))
    }

    @Test(.tags(.claude, .socket))
    func `multiple tags on single test`() {
        #expect(Bool(true))
    }
}

// MARK: - ProviderTagExamples

struct ProviderTagExamples {
    @Test(.tags(.codex))
    func `codex specific behavior`() {
        let transport = "jsonRPC"
        #expect(transport == "jsonRPC")
    }

    @Test(.tags(.gemini))
    func `gemini specific behavior`() {
        let transport = "hookSocket"
        #expect(transport == "hookSocket")
    }

    @Test(.tags(.opencode))
    func `open code specific behavior`() {
        let transport = "httpSSE"
        #expect(transport == "httpSSE")
    }
}
