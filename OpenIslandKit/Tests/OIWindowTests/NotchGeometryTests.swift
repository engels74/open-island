import CoreGraphics
import Foundation
@testable import OIWindow
import Testing

// MARK: - NotchGeometryTests

struct NotchGeometryTests {
    // A typical MacBook Pro 14" screen: 3024×1964 at origin (0, 0)
    // with a notch roughly 180×38 pt.
    static let typicalNotchSize = CGSize(width: 180, height: 38)
    static let typicalScreenFrame = CGRect(x: 0, y: 0, width: 3024, height: 1964)

    static let geometry = NotchGeometry(
        notchSize: typicalNotchSize,
        screenFrame: typicalScreenFrame,
    )

    // MARK: - Device Notch Rect

    @Test
    func `Device notch rect is centered horizontally at screen top`() {
        let geo = Self.geometry
        let expectedX = Self.typicalScreenFrame.width / 2 - Self.typicalNotchSize.width / 2
        let expectedY = Self.typicalScreenFrame.height - Self.typicalNotchSize.height

        #expect(geo.deviceNotchRect.origin.x == expectedX)
        #expect(geo.deviceNotchRect.origin.y == expectedY)
        #expect(geo.deviceNotchRect.width == Self.typicalNotchSize.width)
        #expect(geo.deviceNotchRect.height == Self.typicalNotchSize.height)
    }

    @Test
    func `Device notch rect with non-zero screen origin`() {
        let frame = CGRect(x: 1440, y: 0, width: 3024, height: 1964)
        let geo = NotchGeometry(notchSize: Self.typicalNotchSize, screenFrame: frame)

        // notchX should be relative to screen-local coordinates (subtract screen origin)
        let expectedX = frame.width / 2 - Self.typicalNotchSize.width / 2
        #expect(geo.deviceNotchRect.origin.x == expectedX)
    }

    // MARK: - Padded Notch Rect

    @Test
    func `Padded notch rect is larger than device rect by padding`() {
        let geo = Self.geometry
        let padded = geo.paddedNotchRect
        let device = geo.deviceNotchRect

        // Horizontal padding: ±10pt each side → 20pt wider
        #expect(padded.width == device.width + 20)
        // Vertical padding: ±5pt → 10pt taller
        #expect(padded.height == device.height + 10)
        // Origin shifts left by 10, down by 5
        #expect(padded.origin.x == device.origin.x - 10)
        #expect(padded.origin.y == device.origin.y - 5)
    }

    // MARK: - Hit Testing

    @Test
    func `Point at notch center is inside notch`() {
        let geo = Self.geometry
        let center = CGPoint(
            x: geo.deviceNotchRect.midX,
            y: geo.deviceNotchRect.midY,
        )
        #expect(geo.isPointInNotch(center))
    }

    @Test
    func `Point far from notch is outside`() {
        let geo = Self.geometry
        let farPoint = CGPoint.zero
        #expect(!geo.isPointInNotch(farPoint))
    }

    @Test(arguments: [
        // Inside padding but outside device rect — should still hit
        ("left padding edge", CGPoint(x: 1422 - 10 + 1, y: 1932 + 16), true),
        // Completely outside padding — should miss
        ("well below notch", CGPoint(x: 1512, y: 1900), false),
        ("well left of notch", CGPoint(x: 100, y: 1948), false),
        ("well right of notch", CGPoint(x: 2900, y: 1948), false),
    ])
    func `Hit testing edge cases`(label: String, point: CGPoint, expected: Bool) {
        #expect(Self.geometry.isPointInNotch(point) == expected)
    }

    // MARK: - Coordinate Conversion

    @Test
    func `Notch rect in screen coordinates adds screen origin`() {
        let frame = CGRect(x: 1440, y: 100, width: 3024, height: 1964)
        let geo = NotchGeometry(notchSize: Self.typicalNotchSize, screenFrame: frame)

        let screenCoords = geo.notchRectInScreenCoordinates
        let localCoords = geo.deviceNotchRect

        #expect(screenCoords.origin.x == localCoords.origin.x + frame.origin.x)
        #expect(screenCoords.origin.y == localCoords.origin.y + frame.origin.y)
        #expect(screenCoords.width == localCoords.width)
        #expect(screenCoords.height == localCoords.height)
    }

    @Test
    func `Notch rect in screen coordinates with zero origin matches local coords offset`() {
        let geo = Self.geometry
        let screenCoords = geo.notchRectInScreenCoordinates

        // When screen origin is (0,0), screen coords == local coords
        #expect(screenCoords.origin.x == geo.deviceNotchRect.origin.x)
        #expect(screenCoords.origin.y == geo.deviceNotchRect.origin.y)
    }

    // MARK: - Window Frame

    @Test
    func `Window frame spans full screen width`() {
        let geo = Self.geometry
        let frame = geo.windowFrame

        #expect(frame.width == Self.typicalScreenFrame.width)
        #expect(frame.origin.x == Self.typicalScreenFrame.origin.x)
    }

    @Test
    func `Window frame uses fixed height and sits at screen top`() {
        let geo = Self.geometry
        let frame = geo.windowFrame

        #expect(frame.height == NotchGeometry.windowHeight)
        // Top of window aligns with top of screen
        #expect(frame.maxY == Self.typicalScreenFrame.maxY)
    }

    @Test
    func `Window frame with non-zero screen origin`() {
        let screenFrame = CGRect(x: 1440, y: 200, width: 2560, height: 1440)
        let geo = NotchGeometry(notchSize: Self.typicalNotchSize, screenFrame: screenFrame)
        let frame = geo.windowFrame

        #expect(frame.origin.x == 1440)
        #expect(frame.width == 2560)
        #expect(frame.maxY == screenFrame.maxY)
    }

    // MARK: - Panel Hit Testing

    @Test
    func `Point inside panel bounds returns true`() {
        let geo = Self.geometry
        let panelSize = CGSize(width: 400, height: 300)
        // Center of panel in screen-local coords
        let center = CGPoint(
            x: geo.deviceNotchRect.midX,
            y: Self.typicalScreenFrame.height - 150,
        )
        #expect(geo.isPointInsidePanel(center, size: panelSize))
        #expect(!geo.isPointOutsidePanel(center, size: panelSize))
    }

    @Test
    func `Point outside panel bounds returns false for insidePanel`() {
        let geo = Self.geometry
        let panelSize = CGSize(width: 400, height: 300)
        let outsidePoint = CGPoint.zero
        #expect(!geo.isPointInsidePanel(outsidePoint, size: panelSize))
        #expect(geo.isPointOutsidePanel(outsidePoint, size: panelSize))
    }

    // MARK: - Equatable

    @Test
    func `Identical geometry values are equal`() {
        let a = NotchGeometry(notchSize: Self.typicalNotchSize, screenFrame: Self.typicalScreenFrame)
        let b = NotchGeometry(notchSize: Self.typicalNotchSize, screenFrame: Self.typicalScreenFrame)
        #expect(a == b)
    }

    @Test
    func `Different notch sizes produce unequal geometry`() {
        let a = NotchGeometry(notchSize: CGSize(width: 180, height: 38), screenFrame: Self.typicalScreenFrame)
        let b = NotchGeometry(notchSize: CGSize(width: 224, height: 38), screenFrame: Self.typicalScreenFrame)
        #expect(a != b)
    }
}
