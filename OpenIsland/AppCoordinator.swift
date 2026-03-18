import AppKit
@testable import OICore
@testable import OIModules
@testable import OIProviders
@testable import OIState
@testable import OIUI
@testable import OIWindow
import os
import SwiftUI

// MARK: - AppCoordinator

/// Composition root that instantiates all components and wires them together.
///
/// Owns every long-lived object in the app: screen observer, session store,
/// provider registry, view model, window manager, event monitors, and the
/// activity coordinator. The ``start()`` method boots the full system.
@MainActor
final class AppCoordinator {
    // MARK: Lifecycle

    init() {
        self.screenObserver = ScreenObserver()
        self.sessionStore = SessionStore()
        self.providerRegistry = ProviderRegistry()
        self.soundManager = SoundManager()
        self.moduleRegistry = ModuleRegistry()

        // Register built-in modules.
        self.moduleRegistry.register(MascotModule())
        self.moduleRegistry.register(ActivitySpinnerModule())
        self.moduleRegistry.register(SessionDotsModule())
        self.moduleRegistry.register(PermissionIndicatorModule())
        self.moduleRegistry.register(ReadyCheckmarkModule())
        self.moduleRegistry.register(TimerModule())

        // SessionMonitor bridges the actor-based store to @Observable.
        self.sessionMonitor = SessionMonitor(store: self.sessionStore)

        // NotchViewModel requires geometry — use current or a zero-rect fallback
        // so the view model exists immediately. WindowManager will update it
        // when a notch screen appears.
        let geometry = self.screenObserver.geometry ?? NotchGeometry(
            notchSize: CGSize(width: 200, height: 32),
            screenFrame: .zero,
        )
        self.viewModel = NotchViewModel(geometry: geometry, registry: self.moduleRegistry)

        self.activityCoordinator = NotchActivityCoordinator(
            notchViewModel: self.viewModel,
            sessionMonitor: self.sessionMonitor,
            soundManager: self.soundManager,
        )

        // Capture viewModel directly — `self` isn't fully initialized yet.
        let vm = self.viewModel
        self.eventMonitors = EventMonitors(
            onHoverEnter: {
                vm.notchOpen(reason: .hover)
            },
            onHoverExit: {
                vm.notchClose()
            },
            onClickOutside: {
                vm.notchClose()
            },
            onKeyboardShortcut: {
                if vm.status == .opened {
                    vm.notchClose()
                } else {
                    vm.notchOpen(reason: .click)
                }
            },
            onDrag: { _ in },
        )
        self.eventMonitors.geometry = self.screenObserver.geometry
    }

    // MARK: Internal

    /// Boots the full system: providers, event bridge, window, monitors.
    ///
    /// Call once from the app entry point. Safe to call from a synchronous
    /// context — internally spawns a `Task` for async provider startup.
    func start(updateManager: UpdateManager) {
        self.updateManager = updateManager

        // 1. Register provider adapters.
        let adapters: [any ProviderAdapter] = [
            ClaudeProviderAdapter(),
            CodexProviderAdapter(),
            GeminiCLIProviderAdapter(),
            OpenCodeProviderAdapter(),
        ]

        Task {
            for adapter in adapters {
                await self.providerRegistry.register(adapter)
            }

            // 2. Start each provider individually — best effort.
            for adapter in adapters {
                do {
                    try await adapter.start()
                } catch {
                    self.logger.warning("Provider \(adapter.providerID.rawValue) failed to start: \(error)")
                }
            }

            // 3. Start the event bridge: provider events → session store.
            let mergedStream = await self.providerRegistry.mergedEvents()
            self.eventBridgeTask = Task {
                for await event in mergedStream {
                    await self.sessionStore.process(.providerEvent(event))
                }
            }
        }

        // 4. Start SessionMonitor.
        self.sessionMonitor.start()

        // 5. Create WindowManager with factory closure.
        self.windowManager = WindowManager(
            screenObserver: self.screenObserver,
        ) { [weak self] geometry in
            guard let self else {
                fatalError("AppCoordinator deallocated before window factory invoked")
            }
            self.viewModel.geometry = geometry
            let notchView = NotchView(
                viewModel: self.viewModel,
                sessionMonitor: self.sessionMonitor,
            ) { [weak self] in
                self?.updateManager?.checkForUpdates()
            }
            return NotchWindowControllerAdapter(
                geometry: geometry,
                content: AnyView(notchView),
                viewModel: self.viewModel,
            )
        }
        self.windowManager?.start()

        // 6. Start EventMonitors.
        self.eventMonitors.startAll()

        // 7. Start NotchActivityCoordinator.
        self.activityCoordinator.start()
    }

    // MARK: Private

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "OpenIsland",
        category: "AppCoordinator",
    )

    private let screenObserver: ScreenObserver
    private let sessionStore: SessionStore
    private let providerRegistry: ProviderRegistry
    private let soundManager: SoundManager
    private let moduleRegistry: ModuleRegistry
    private let sessionMonitor: SessionMonitor
    private let viewModel: NotchViewModel
    private let activityCoordinator: NotchActivityCoordinator
    private let eventMonitors: EventMonitors

    private var windowManager: WindowManager?
    private weak var updateManager: UpdateManager?
    private var eventBridgeTask: Task<Void, Never>?
}
