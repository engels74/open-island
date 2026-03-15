@testable import OIWindow
import Testing

// MARK: - OpenReasonTests

struct OpenReasonTests {
    // MARK: - shouldActivate

    @Test
    func `User-initiated reasons should activate the app`() {
        #expect(OpenReason.click.shouldActivate)
        #expect(OpenReason.hover.shouldActivate)
    }

    @Test
    func `Programmatic reasons should not activate the app`() {
        #expect(!OpenReason.notification.shouldActivate)
        #expect(!OpenReason.boot.shouldActivate)
    }

    @Test(
        arguments: [
            (OpenReason.click, true),
            (OpenReason.hover, true),
            (OpenReason.notification, false),
            (OpenReason.boot, false),
        ],
    )
    func `shouldActivate returns expected value for each reason`(reason: OpenReason, expected: Bool) {
        #expect(reason.shouldActivate == expected)
    }
}
