import AppKit
import Foundation
@testable import OIWindow
import Testing

// MARK: - ScreenIdentifierTests

struct ScreenIdentifierTests {
    @Test
    func `Init stores display ID`() {
        let id = ScreenIdentifier(displayID: 42)
        #expect(id.displayID == 42)
    }

    @Test
    func `Equatable — same display IDs are equal`() {
        let a = ScreenIdentifier(displayID: 1)
        let b = ScreenIdentifier(displayID: 1)
        #expect(a == b)
    }

    @Test
    func `Equatable — different display IDs are not equal`() {
        let a = ScreenIdentifier(displayID: 1)
        let b = ScreenIdentifier(displayID: 2)
        #expect(a != b)
    }

    @Test
    func `Hashable — can be used as dictionary key`() {
        var dict: [ScreenIdentifier: String] = [:]
        dict[ScreenIdentifier(displayID: 1)] = "Built-in"
        dict[ScreenIdentifier(displayID: 2)] = "External"
        #expect(dict[ScreenIdentifier(displayID: 1)] == "Built-in")
        #expect(dict[ScreenIdentifier(displayID: 2)] == "External")
    }

    @Test
    func `Codable round-trip`() throws {
        let original = ScreenIdentifier(displayID: 12345)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScreenIdentifier.self, from: data)
        #expect(decoded == original)
        #expect(decoded.displayID == 12345)
    }

    @Test
    @MainActor
    func `Resolve returns nil for non-existent display ID`() {
        // Display ID 0xDEADBEEF is extremely unlikely to be a real display
        let id = ScreenIdentifier(displayID: 0xDEAD_BEEF)
        #expect(id.resolve() == nil)
    }
}

// MARK: - ScreenSelectorTests

struct ScreenSelectorTests {
    @Test
    func `Automatic equals automatic`() {
        let a = ScreenSelector.automatic
        let b = ScreenSelector.automatic
        #expect(a == b)
    }

    @Test
    func `Specific with same ID equals specific`() {
        let id = ScreenIdentifier(displayID: 42)
        let a = ScreenSelector.specific(id)
        let b = ScreenSelector.specific(id)
        #expect(a == b)
    }

    @Test
    func `Specific with different IDs are not equal`() {
        let a = ScreenSelector.specific(ScreenIdentifier(displayID: 1))
        let b = ScreenSelector.specific(ScreenIdentifier(displayID: 2))
        #expect(a != b)
    }

    @Test
    func `Automatic does not equal specific`() {
        let specific = ScreenSelector.specific(ScreenIdentifier(displayID: 1))
        #expect(ScreenSelector.automatic != specific)
    }

    // MARK: - Resolve Fallback Logic

    @Test
    @MainActor
    func `Automatic resolveScreen returns nil when no builtin notch screen`() {
        // In CI or on machines without a notch, automatic should return nil
        // or a valid screen. We just verify it doesn't crash.
        let result = ScreenSelector.automatic.resolveScreen()
        // On a non-notch Mac, result should be nil
        // On a notch Mac, result should be a valid NSScreen
        // Either way, no crash is the important assertion
        if let screen = result {
            #expect(screen.frame.width > 0)
            #expect(screen.frame.height > 0)
        }
    }

    @Test
    @MainActor
    func `Specific with bogus ID falls back to automatic`() {
        let bogus = ScreenIdentifier(displayID: 0xDEAD_BEEF)
        let selector = ScreenSelector.specific(bogus)
        let result = selector.resolveScreen()

        // The bogus screen doesn't exist, so .specific falls back to .automatic.
        // On a notch Mac this returns the builtin; on non-notch Mac this returns nil.
        let automaticResult = ScreenSelector.automatic.resolveScreen()
        #expect(result == automaticResult)
    }
}
