import CoreGraphics
import Foundation
@testable import OIWindow
import SwiftUI
import Testing

// MARK: - NotchShapeTests

struct NotchShapeTests {
    // MARK: - Path Bounds

    @Test
    func `Path fills the given rect`() {
        let shape = NotchShape()
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = shape.path(in: rect)
        let bounds = path.boundingRect

        // The path should stay within the rect (allowing small floating-point tolerance)
        #expect(bounds.minX >= rect.minX - 0.5)
        #expect(bounds.minY >= rect.minY - 0.5)
        #expect(bounds.maxX <= rect.maxX + 0.5)
        #expect(bounds.maxY <= rect.maxY + 0.5)
    }

    @Test
    func `Path is non-empty for a valid rect`() {
        let shape = NotchShape()
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = shape.path(in: rect)
        #expect(!path.isEmpty)
    }

    @Test
    func `Path contains center point of rect`() {
        let shape = NotchShape()
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let path = shape.path(in: rect)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        #expect(path.contains(center))
    }

    // MARK: - Corner Radii

    @Test(arguments: [
        ("default", NotchShape(), 6 as CGFloat, 14 as CGFloat),
        ("zero radii", NotchShape(topCornerRadius: 0, bottomCornerRadius: 0), 0, 0),
        ("large radii", NotchShape(topCornerRadius: 30, bottomCornerRadius: 30), 30, 30),
        ("asymmetric", NotchShape(topCornerRadius: 4, bottomCornerRadius: 20), 4, 20),
    ])
    func `Corner radii are stored correctly`(
        label: String,
        shape: NotchShape,
        expectedTop: CGFloat,
        expectedBottom: CGFloat,
    ) {
        #expect(shape.topCornerRadius == expectedTop)
        #expect(shape.bottomCornerRadius == expectedBottom)
    }

    @Test
    func `Different corner radii produce valid paths`() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)

        let closed = NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        let opened = NotchShape(topCornerRadius: 12, bottomCornerRadius: 24)

        let closedPath = closed.path(in: rect)
        let openedPath = opened.path(in: rect)

        // Both should produce non-empty paths within bounds
        #expect(!closedPath.isEmpty)
        #expect(!openedPath.isEmpty)
        #expect(closedPath.boundingRect.width <= rect.width + 1)
        #expect(openedPath.boundingRect.width <= rect.width + 1)
    }

    // MARK: - Radius Clamping

    @Test
    func `Radii exceeding half dimension are clamped`() {
        // Rect is 40×20, so half-width=20, half-height=10
        // Radii of 50 should be clamped to 10 (min of halfWidth, halfHeight)
        let shape = NotchShape(topCornerRadius: 50, bottomCornerRadius: 50)
        let rect = CGRect(x: 0, y: 0, width: 40, height: 20)
        let path = shape.path(in: rect)

        #expect(!path.isEmpty)
        // Path should still be contained within the rect
        let bounds = path.boundingRect
        #expect(bounds.maxX <= rect.maxX + 0.5)
        #expect(bounds.maxY <= rect.maxY + 0.5)
    }

    // MARK: - Zero-Size Rect

    @Test
    func `Path in zero-size rect is empty`() {
        let shape = NotchShape()
        let path = shape.path(in: .zero)
        #expect(path.boundingRect.width <= 0.001)
        #expect(path.boundingRect.height <= 0.001)
    }

    // MARK: - AnimatableData

    @Test
    func `AnimatableData round-trips correctly`() {
        var shape = NotchShape(topCornerRadius: 10, bottomCornerRadius: 20)
        let data = shape.animatableData
        #expect(data.first == 10)
        #expect(data.second == 20)

        shape.animatableData = .init(30, 40)
        #expect(shape.topCornerRadius == 30)
        #expect(shape.bottomCornerRadius == 40)
    }

    // MARK: - Non-Zero Origin

    @Test
    func `Path respects non-zero rect origin`() {
        let shape = NotchShape()
        let rect = CGRect(x: 100, y: 50, width: 200, height: 100)
        let path = shape.path(in: rect)
        let bounds = path.boundingRect

        // Path should be positioned relative to the rect's origin
        #expect(bounds.minX >= rect.minX - 0.5)
        #expect(bounds.minY >= rect.minY - 0.5)
        #expect(bounds.maxX <= rect.maxX + 0.5)
        #expect(bounds.maxY <= rect.maxY + 0.5)
    }
}
