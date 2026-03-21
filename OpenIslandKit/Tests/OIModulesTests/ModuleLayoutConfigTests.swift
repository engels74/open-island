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

// MARK: - ModuleLayoutConfigTests

struct ModuleLayoutConfigTests {
    // MARK: - Codable round-trip

    @Test
    func `Encode and decode preserves entries`() throws {
        let original = ModuleLayoutConfig(entries: [
            ModuleLayoutEntry(moduleID: "mod1", side: .left, order: 0),
            ModuleLayoutEntry(moduleID: "mod2", side: .right, order: 1, isHidden: true),
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModuleLayoutConfig.self, from: data)

        #expect(decoded.entries.count == 2)
        #expect(decoded.entries[0].moduleID == "mod1")
        #expect(decoded.entries[0].side == .left)
        #expect(decoded.entries[0].order == 0)
        #expect(decoded.entries[0].isHidden == false)
        #expect(decoded.entries[1].moduleID == "mod2")
        #expect(decoded.entries[1].side == .right)
        #expect(decoded.entries[1].order == 1)
        #expect(decoded.entries[1].isHidden == true)
    }

    @Test
    func `Empty config round-trips correctly`() throws {
        let original = ModuleLayoutConfig()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModuleLayoutConfig.self, from: data)

        #expect(decoded.entries.isEmpty)
    }

    // MARK: - Reconciliation: stale pruning

    @Test
    func `Reconcile prunes stale entries`() {
        var config = ModuleLayoutConfig(entries: [
            ModuleLayoutEntry(moduleID: "existing", side: .left, order: 0),
            ModuleLayoutEntry(moduleID: "stale", side: .right, order: 1),
        ])

        let registeredModules: [any NotchModule] = [
            MockModule(id: "existing", side: .left, order: 0),
        ]

        config.reconcile(with: registeredModules)

        #expect(config.entries.count == 1)
        #expect(config.entries[0].moduleID == "existing")
    }

    @Test
    func `Reconcile prunes all entries when registry is empty`() {
        var config = ModuleLayoutConfig(entries: [
            ModuleLayoutEntry(moduleID: "a", side: .left, order: 0),
            ModuleLayoutEntry(moduleID: "b", side: .right, order: 1),
        ])

        config.reconcile(with: [])

        #expect(config.entries.isEmpty)
    }

    // MARK: - Reconciliation: new module addition

    @Test
    func `Reconcile adds new modules at default positions`() throws {
        var config = ModuleLayoutConfig(entries: [
            ModuleLayoutEntry(moduleID: "existing", side: .left, order: 0),
        ])

        let registeredModules: [any NotchModule] = [
            MockModule(id: "existing", side: .left, order: 0),
            MockModule(id: "brand-new", side: .right, order: 5),
        ]

        config.reconcile(with: registeredModules)

        #expect(config.entries.count == 2)
        let newEntry = config.entries.first { $0.moduleID == "brand-new" }
        let found = try #require(newEntry)
        #expect(found.side == .right)
        #expect(found.order == 5)
        #expect(found.isHidden == false)
    }

    @Test
    func `Reconcile from empty config adds all modules`() {
        var config = ModuleLayoutConfig()

        let registeredModules: [any NotchModule] = [
            MockModule(id: "m1", side: .left, order: 0),
            MockModule(id: "m2", side: .right, order: 1),
            MockModule(id: "m3", side: .left, order: 2),
        ]

        config.reconcile(with: registeredModules)

        #expect(config.entries.count == 3)
        let ids = config.entries.map(\.moduleID)
        #expect(ids.contains("m1"))
        #expect(ids.contains("m2"))
        #expect(ids.contains("m3"))
    }

    // MARK: - Reconciliation: combined prune + add

    @Test
    func `Reconcile simultaneously prunes stale and adds new`() {
        var config = ModuleLayoutConfig(entries: [
            ModuleLayoutEntry(moduleID: "keep", side: .left, order: 0),
            ModuleLayoutEntry(moduleID: "remove", side: .right, order: 1),
        ])

        let registeredModules: [any NotchModule] = [
            MockModule(id: "keep", side: .left, order: 0),
            MockModule(id: "add", side: .right, order: 2),
        ]

        config.reconcile(with: registeredModules)

        let ids = config.entries.map(\.moduleID)
        #expect(ids.contains("keep"))
        #expect(ids.contains("add"))
        #expect(!ids.contains("remove"))
        #expect(config.entries.count == 2)
    }

    // MARK: - Hidden modules

    @Test
    func `isHidden returns true for hidden entry`() {
        let config = ModuleLayoutConfig(entries: [
            ModuleLayoutEntry(moduleID: "hidden-mod", side: .left, order: 0, isHidden: true),
        ])

        #expect(config.isHidden("hidden-mod"))
    }

    @Test
    func `isHidden returns false for visible entry`() {
        let config = ModuleLayoutConfig(entries: [
            ModuleLayoutEntry(moduleID: "visible-mod", side: .left, order: 0, isHidden: false),
        ])

        #expect(!config.isHidden("visible-mod"))
    }

    @Test
    func `isHidden returns false for unknown module`() {
        let config = ModuleLayoutConfig()
        #expect(!config.isHidden("unknown"))
    }

    // MARK: - Effective side and order

    @Test
    func `effectiveSide returns persisted side`() {
        let config = ModuleLayoutConfig(entries: [
            ModuleLayoutEntry(moduleID: "mod", side: .right, order: 0),
        ])

        let module = MockModule(id: "mod", side: .left, order: 0)
        #expect(config.effectiveSide(for: module) == .right)
    }

    @Test
    func `effectiveSide falls back to module default`() {
        let config = ModuleLayoutConfig()
        let module = MockModule(id: "untracked", side: .left, order: 0)
        #expect(config.effectiveSide(for: module) == .left)
    }

    @Test
    func `effectiveOrder returns persisted order`() {
        let config = ModuleLayoutConfig(entries: [
            ModuleLayoutEntry(moduleID: "mod", side: .left, order: 99),
        ])

        let module = MockModule(id: "mod", side: .left, order: 0)
        #expect(config.effectiveOrder(for: module) == 99)
    }

    @Test
    func `effectiveOrder falls back to module default`() {
        let config = ModuleLayoutConfig()
        let module = MockModule(id: "untracked", side: .left, order: 42)
        #expect(config.effectiveOrder(for: module) == 42)
    }
}
