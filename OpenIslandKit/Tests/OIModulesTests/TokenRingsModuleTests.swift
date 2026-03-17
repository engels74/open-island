import Foundation
import OICore
@testable import OIModules
import Testing

@MainActor
struct TokenRingsModuleTests {
    @Test
    func `Module has correct defaults`() {
        let module = TokenRingsModule()

        #expect(module.id == "tokenRings")
        #expect(module.defaultSide == .right)
        #expect(module.defaultOrder == 4)
        #expect(!module.showInExpandedHeader)
    }

    @Test
    func `Preferred width is compact`() {
        let module = TokenRingsModule()
        let width: CGFloat = 22
        #expect(module.preferredWidth() == width)
    }

    @Test
    func `Visible when providers are active`() {
        let module = TokenRingsModule()
        let context = ModuleVisibilityContext(activeProviders: [.claude])
        #expect(module.isVisible(context: context))
    }

    @Test
    func `Not visible when no providers`() {
        let module = TokenRingsModule()
        let context = ModuleVisibilityContext()
        #expect(!module.isVisible(context: context))
    }

    @Test
    func `Order is after timer module`() {
        let module = TokenRingsModule()
        // Timer is order 3; token rings should be order 4
        #expect(module.defaultOrder > 3)
    }
}
