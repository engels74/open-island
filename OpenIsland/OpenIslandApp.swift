import AppKit
import OICore
import os
import SwiftUI

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by ``OpenIslandApp`` so the delegate can call ``AppCoordinator/stop()`` on termination.
    var coordinator: AppCoordinator?

    func applicationWillTerminate(_: Notification) {
        self.coordinator?.stop()
    }
}

// MARK: - OpenIslandApp

@main
struct OpenIslandApp: App {
    // MARK: Lifecycle

    init() {
        SingleInstanceGuard.ensureSingleInstance()
        NSApplication.shared.setActivationPolicy(.accessory)
        self.updateManager.start()
        self.coordinator.start(updateManager: self.updateManager)
        self.appDelegate.coordinator = self.coordinator
    }

    // MARK: Internal

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate // swiftlint:disable:this attributes

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }

    // MARK: Private

    @State private var updateManager = UpdateManager()
    @State private var coordinator = AppCoordinator()
}
