@testable import OICore
import Testing

// MARK: - TagUsageExampleTests

struct TagUsageExampleTests {
    @Test(.tags(.claude))
    func claudeTaggedFilterCorrectly() {
        // Run with: swift test --filter .tags:claude
        #expect(Bool(true))
    }

    @Test(.tags(.socket))
    func socketTaggedTransportLayer() {
        // Run with: swift test --filter .tags:socket
        #expect(Bool(true))
    }

    @Test(.tags(.ui))
    func uiTaggedViewLayer() {
        #expect(Bool(true))
    }

    @Test(.tags(.claude, .socket))
    func multipleTagsOnSingleTest() {
        // Tests can carry multiple tags for cross-cutting filtering
        #expect(Bool(true))
    }
}

// MARK: - ProviderTagExamples

struct ProviderTagExamples {
    @Test(.tags(.codex))
    func codexSpecificBehavior() {
        let transport = "jsonRPC"
        #expect(transport == "jsonRPC")
    }

    @Test(.tags(.gemini))
    func geminiSpecificBehavior() {
        let transport = "hookSocket"
        #expect(transport == "hookSocket")
    }

    @Test(.tags(.opencode))
    func openCodeSpecificBehavior() {
        let transport = "httpSSE"
        #expect(transport == "httpSSE")
    }
}
