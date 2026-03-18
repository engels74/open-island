import AppKit
@testable import OICore
import SwiftUI

@main
struct OpenIslandApp: App {
    // MARK: Lifecycle

    init() {
        SingleInstanceGuard.ensureSingleInstance()
        NSApplication.shared.setActivationPolicy(.accessory)
        self.updateManager.start()
        self.coordinator.start(updateManager: self.updateManager)
    }

    // MARK: Internal

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }

    // MARK: Private

    @State private var updateManager = UpdateManager()
    @State private var coordinator = AppCoordinator()
}
