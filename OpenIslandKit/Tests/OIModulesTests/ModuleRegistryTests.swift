import Foundation
@testable import OIModules
import SwiftUI
import Testing

// MARK: - MockModule

private struct MockModule: NotchModule {
    // MARK: Lifecycle

    init(id: String, side: ModuleSide = .left, order: Int = 0) {
        self.id = id
        self.defaultSide = side
        self.defaultOrder = order
    }

    // MARK: Internal

    let id: String
    let defaultSide: ModuleSide
    let defaultOrder: Int
    let showInExpandedHeader = false

    func isVisible(context: ModuleVisibilityContext) -> Bool {
        true
    }

    func preferredWidth() -> CGFloat {
        20
    }

    @MainActor
    func makeBody(context: ModuleRenderContext) -> AnyView {
        AnyView(EmptyView())
    }
}

// MARK: - ModuleRegistryTests

@MainActor
struct ModuleRegistryTests {
    // MARK: - Registration

    @Test
    func `Register adds module to allModules`() {
        let registry = ModuleRegistry()
        registry.register(MockModule(id: "test"))

        #expect(registry.allModules.count == 1)
        #expect(registry.allModules[0].id == "test")
    }

    @Test
    func `Duplicate registration is ignored`() {
        let registry = ModuleRegistry()
        registry.register(MockModule(id: "dup", side: .left, order: 0))
        registry.register(MockModule(id: "dup", side: .right, order: 1))

        #expect(registry.allModules.count == 1)
        #expect(registry.allModules[0].defaultSide == .left)
    }

    @Test
    func `Multiple unique modules are all registered`() {
        let registry = ModuleRegistry()
        registry.register(MockModule(id: "a"))
        registry.register(MockModule(id: "b"))
        registry.register(MockModule(id: "c"))

        #expect(registry.allModules.count == 3)
    }

    // MARK: - Filtering by side

    @Test
    func `Modules filtered by side returns correct subset`() {
        let registry = ModuleRegistry()
        registry.register(MockModule(id: "l1", side: .left, order: 0))
        registry.register(MockModule(id: "l2", side: .left, order: 1))
        registry.register(MockModule(id: "r1", side: .right, order: 0))

        let leftModules = registry.modules(for: .left)
        let rightModules = registry.modules(for: .right)

        #expect(leftModules.count == 2)
        #expect(rightModules.count == 1)
        #expect(leftModules.allSatisfy { $0.defaultSide == .left })
        #expect(rightModules.allSatisfy { $0.defaultSide == .right })
    }

    // MARK: - Ordering

    @Test
    func `Modules for side are sorted by defaultOrder`() {
        let registry = ModuleRegistry()
        registry.register(MockModule(id: "order2", side: .left, order: 2))
        registry.register(MockModule(id: "order0", side: .left, order: 0))
        registry.register(MockModule(id: "order1", side: .left, order: 1))

        let sorted = registry.modules(for: .left)
        let ids = sorted.map(\.id)
        #expect(ids == ["order0", "order1", "order2"])
    }

    @Test
    func `Modules for side with no matches returns empty`() {
        let registry = ModuleRegistry()
        registry.register(MockModule(id: "left-only", side: .left))

        let rightModules = registry.modules(for: .right)
        #expect(rightModules.isEmpty)
    }

    // MARK: - Empty registry

    @Test
    func `Empty registry returns empty for both sides`() {
        let registry = ModuleRegistry()

        #expect(registry.allModules.isEmpty)
        #expect(registry.modules(for: .left).isEmpty)
        #expect(registry.modules(for: .right).isEmpty)
    }
}
