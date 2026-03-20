import AppKit
import CoreGraphics
@testable import OIWindow
import Testing

// MARK: - NSScreenNotchTests

/// Tests for the `NSScreen+Notch` extension.
///
/// Many properties depend on real display hardware, so tests that need a physical
/// notch are guarded and skip gracefully on non-notch machines (e.g. CI).
struct NSScreenNotchTests {
    // MARK: - Safety Padding

    @Test
    @MainActor
    func `Notch size includes safety padding on notch displays`() {
        guard let screen = NSScreen.builtin, screen.hasPhysicalNotch else { return }

        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        let rawWidth = screen.frame.width - leftWidth - rightWidth
        guard rawWidth > 0 else { return }

        // notchSize should be exactly 24pt wider than the raw exclusion width (12pt per side).
        let notchSize = screen.notchSize
        #expect(notchSize != nil)
        #expect(notchSize?.width == rawWidth + 24)
    }

    @Test
    @MainActor
    func `Reserved exclusion width is 24pt wider than base width`() {
        guard let screen = NSScreen.builtin, screen.hasPhysicalNotch else { return }

        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        let rawWidth = screen.frame.width - leftWidth - rightWidth
        guard rawWidth > 0 else { return }

        #expect(screen.reservedNotchExclusionWidth == rawWidth + 24)
    }

    // MARK: - Non-Notch Displays

    @Test
    @MainActor
    func `Non-notch screen returns nil notchSize`() {
        // External monitors don't have a notch.
        for screen in NSScreen.screens where !screen.hasPhysicalNotch {
            #expect(screen.notchSize == nil)
        }
    }

    // MARK: - Built-in Display

    @Test
    @MainActor
    func `Builtin returns a screen or nil without crashing`() {
        // Verify the static accessor doesn't crash on any machine.
        let builtin = NSScreen.builtin
        if let builtin {
            #expect(builtin.frame.width > 0)
        }
    }
}
