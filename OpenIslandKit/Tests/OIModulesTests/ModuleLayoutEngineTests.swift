import Foundation
@testable import OIModules
import SwiftUI
import Testing

// MARK: - MockModule

private struct MockModule: NotchModule {
    // MARK: Lifecycle

    init(
        id: String,
        side: ModuleSide,
        order: Int,
        width: CGFloat = 20,
        isVisible: Bool = true,
    ) {
        self.id = id
        self.defaultSide = side
        self.defaultOrder = order
        self._preferredWidth = width
        self._isVisible = isVisible
    }

    // MARK: Internal

    let id: String
    let defaultSide: ModuleSide
    let defaultOrder: Int
    let showInExpandedHeader = false

    func isVisible(context: ModuleVisibilityContext) -> Bool {
        self._isVisible
    }

    func preferredWidth() -> CGFloat {
        self._preferredWidth
    }

    @MainActor
    func makeBody(context: ModuleRenderContext) -> AnyView {
        AnyView(EmptyView())
    }

    // MARK: Private

    private let _preferredWidth: CGFloat
    private let _isVisible: Bool
}

// MARK: - ModuleLayoutEngineTests

struct ModuleLayoutEngineTests {
    // MARK: - Zero modules

    @Test
    func `Zero modules produces zero-width result`() {
        let result = ModuleLayoutEngine.layout(
            modules: [],
            context: ModuleVisibilityContext(),
        )

        #expect(result.modules.isEmpty)
        #expect(result.symmetricSideWidth == 0)
        #expect(result.totalExpansionWidth == 0)
        #expect(result.leftNaturalWidth == 0)
        #expect(result.rightNaturalWidth == 0)
    }

    // MARK: - All modules hidden

    @Test
    func `All modules invisible produces zero-width result`() {
        let modules: [any NotchModule] = [
            MockModule(id: "a", side: .left, order: 0, isVisible: false),
            MockModule(id: "b", side: .right, order: 0, isVisible: false),
        ]

        let result = ModuleLayoutEngine.layout(
            modules: modules,
            context: ModuleVisibilityContext(),
        )

        #expect(result.modules.isEmpty)
        #expect(result.symmetricSideWidth == 0)
        #expect(result.totalExpansionWidth == 0)
    }

    // MARK: - Single module per side

    @Test
    func `Single left module layout`() {
        let modules: [any NotchModule] = [
            MockModule(id: "left1", side: .left, order: 0, width: 20),
        ]

        let result = ModuleLayoutEngine.layout(
            modules: modules,
            context: ModuleVisibilityContext(),
        )

        #expect(result.modules.count == 1)

        let layout = result.modules[0]
        #expect(layout.moduleID == "left1")
        #expect(layout.side == .left)
        #expect(layout.offsetFromEdge == ModuleLayoutEngine.outerEdgeInset)
        #expect(layout.width == 20)

        // Natural width = outerEdgeInset(6) + width(20) = 26
        #expect(result.leftNaturalWidth == 26)
        #expect(result.rightNaturalWidth == 0)
        #expect(result.symmetricSideWidth == 26)
        #expect(result.totalExpansionWidth == 52)
    }

    @Test
    func `Single right module layout`() {
        let modules: [any NotchModule] = [
            MockModule(id: "right1", side: .right, order: 0, width: 30),
        ]

        let result = ModuleLayoutEngine.layout(
            modules: modules,
            context: ModuleVisibilityContext(),
        )

        #expect(result.modules.count == 1)

        let layout = result.modules[0]
        #expect(layout.moduleID == "right1")
        #expect(layout.side == .right)
        #expect(layout.width == 30)

        // Natural width = outerEdgeInset(6) + width(30) = 36
        #expect(result.rightNaturalWidth == 36)
        #expect(result.leftNaturalWidth == 0)
        #expect(result.symmetricSideWidth == 36)
    }

    // MARK: - Multiple modules with spacing

    @Test
    func `Two modules on same side include inter-module spacing`() {
        let modules: [any NotchModule] = [
            MockModule(id: "l1", side: .left, order: 0, width: 20),
            MockModule(id: "l2", side: .left, order: 1, width: 30),
        ]

        let result = ModuleLayoutEngine.layout(
            modules: modules,
            context: ModuleVisibilityContext(),
        )

        #expect(result.modules.count == 2)

        let first = result.modules[0]
        let second = result.modules[1]
        #expect(first.moduleID == "l1")
        #expect(second.moduleID == "l2")

        // First: offset = outerEdgeInset(6)
        #expect(first.offsetFromEdge == 6)
        // Second: offset = 6 + 20 + 8(spacing) = 34
        #expect(second.offsetFromEdge == 34)

        // Natural width = 6 + 20 + 8 + 30 = 64
        #expect(result.leftNaturalWidth == 64)
    }

    @Test
    func `Three modules include spacing between each pair`() {
        let modules: [any NotchModule] = [
            MockModule(id: "r1", side: .right, order: 0, width: 10),
            MockModule(id: "r2", side: .right, order: 1, width: 15),
            MockModule(id: "r3", side: .right, order: 2, width: 20),
        ]

        let result = ModuleLayoutEngine.layout(
            modules: modules,
            context: ModuleVisibilityContext(),
        )

        #expect(result.modules.count == 3)

        // Natural width = 6 + 10 + 8 + 15 + 8 + 20 = 67
        #expect(result.rightNaturalWidth == 67)
    }

    // MARK: - Symmetric width calculation

    @Test
    func `Left wider than right enforces symmetry`() {
        let modules: [any NotchModule] = [
            MockModule(id: "l1", side: .left, order: 0, width: 50),
            MockModule(id: "r1", side: .right, order: 0, width: 20),
        ]

        let result = ModuleLayoutEngine.layout(
            modules: modules,
            context: ModuleVisibilityContext(),
        )

        // Left natural = 6 + 50 = 56
        // Right natural = 6 + 20 = 26
        #expect(result.leftNaturalWidth == 56)
        #expect(result.rightNaturalWidth == 26)
        #expect(result.symmetricSideWidth == 56)
        #expect(result.totalExpansionWidth == 112)
    }

    @Test
    func `Right wider than left enforces symmetry`() {
        let modules: [any NotchModule] = [
            MockModule(id: "l1", side: .left, order: 0, width: 10),
            MockModule(id: "r1", side: .right, order: 0, width: 40),
        ]

        let result = ModuleLayoutEngine.layout(
            modules: modules,
            context: ModuleVisibilityContext(),
        )

        // Left natural = 6 + 10 = 16
        // Right natural = 6 + 40 = 46
        #expect(result.leftNaturalWidth == 16)
        #expect(result.rightNaturalWidth == 46)
        #expect(result.symmetricSideWidth == 46)
        #expect(result.totalExpansionWidth == 92)
    }

    @Test
    func `Equal sides produce equal symmetric width`() {
        let modules: [any NotchModule] = [
            MockModule(id: "l1", side: .left, order: 0, width: 20),
            MockModule(id: "r1", side: .right, order: 0, width: 20),
        ]

        let result = ModuleLayoutEngine.layout(
            modules: modules,
            context: ModuleVisibilityContext(),
        )

        #expect(result.leftNaturalWidth == result.rightNaturalWidth)
        #expect(result.symmetricSideWidth == 26) // 6 + 20
        #expect(result.totalExpansionWidth == 52)
    }

    // MARK: - Mixed visibility

    @Test
    func `Only visible modules are laid out`() {
        let modules: [any NotchModule] = [
            MockModule(id: "visible-left", side: .left, order: 0, width: 20, isVisible: true),
            MockModule(id: "hidden-left", side: .left, order: 1, width: 30, isVisible: false),
            MockModule(id: "visible-right", side: .right, order: 0, width: 25, isVisible: true),
        ]

        let result = ModuleLayoutEngine.layout(
            modules: modules,
            context: ModuleVisibilityContext(),
        )

        #expect(result.modules.count == 2)
        let ids = result.modules.map(\.moduleID)
        #expect(ids.contains("visible-left"))
        #expect(ids.contains("visible-right"))
        #expect(!ids.contains("hidden-left"))

        // Left natural = 6 + 20 = 26 (hidden module excluded)
        #expect(result.leftNaturalWidth == 26)
        // Right natural = 6 + 25 = 31
        #expect(result.rightNaturalWidth == 31)
    }

    // MARK: - Ordering

    @Test
    func `Modules are sorted by defaultOrder within each side`() {
        let modules: [any NotchModule] = [
            MockModule(id: "l-order2", side: .left, order: 2, width: 10),
            MockModule(id: "l-order0", side: .left, order: 0, width: 10),
            MockModule(id: "l-order1", side: .left, order: 1, width: 10),
        ]

        let result = ModuleLayoutEngine.layout(
            modules: modules,
            context: ModuleVisibilityContext(),
        )

        let ids = result.modules.map(\.moduleID)
        #expect(ids == ["l-order0", "l-order1", "l-order2"])
    }

    // MARK: - Output structure

    @Test
    func `Result modules are partitioned left then right`() {
        let modules: [any NotchModule] = [
            MockModule(id: "r1", side: .right, order: 0, width: 10),
            MockModule(id: "l1", side: .left, order: 0, width: 10),
        ]

        let result = ModuleLayoutEngine.layout(
            modules: modules,
            context: ModuleVisibilityContext(),
        )

        #expect(result.modules.count == 2)
        #expect(result.modules[0].side == .left)
        #expect(result.modules[1].side == .right)
    }

    // MARK: - Constants

    @Test
    func `Inter-module spacing is 8 points`() {
        #expect(ModuleLayoutEngine.interModuleSpacing == 8)
    }

    @Test
    func `Outer edge inset is 6 points`() {
        #expect(ModuleLayoutEngine.outerEdgeInset == 6)
    }
}
