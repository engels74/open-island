import AppKit
import SwiftUI

@main
struct OpenIslandApp: App {
    // MARK: Lifecycle

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    // MARK: Internal

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
