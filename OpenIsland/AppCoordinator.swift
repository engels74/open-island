import AppKit
import Observation
import OICore
import OIModules
import OIProviders
import OIState
import OIUI
import OIWindow
import os
import SwiftUI
import Synchronization

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
        self.setupCoordinator = ProviderSetupCoordinator()
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
            onClickOutside: { _ in
                vm.notchClose()
            },
            onClickNotch: {
                vm.notchOpen(reason: .click)
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

    let setupCoordinator: ProviderSetupCoordinator

    /// Boots the full system: providers, event bridge, window, monitors.
    ///
    /// Call once from the app entry point. Safe to call from a synchronous
    /// context — internally spawns a `Task` for async provider startup.
    func start(updateManager: UpdateManager) {
        self.updateManager = updateManager

        // 1. Register all provider adapters (so they're available for later enable/disable).
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

            // 2. Only start providers that are enabled in settings.
            let failures = await self.providerRegistry.startEnabledProviders()
            for (id, error) in failures {
                self.logger.warning("Provider \(id.rawValue) failed to start: \(error)")
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
        let setupActions = self.makeSetupActions()
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
                activityCoordinator: self.activityCoordinator,
                onCheckForUpdates: { [weak self] in
                    self?.updateManager?.checkForUpdates()
                },
                setupActions: setupActions,
            )
            return NotchWindowControllerAdapter(
                geometry: geometry,
                content: AnyView(notchView),
                viewModel: self.viewModel,
            )
        }
        self.windowManager?.start()

        // 6. Start EventMonitors.
        self.eventMonitors.startAll()

        // 7. Keep EventMonitors geometry in sync with ScreenObserver.
        self.geometryObservationTask = self.startGeometryObservation()

        // 8. Wire panel size so EventMonitors knows the opened panel bounds.
        self.panelSizeObservationTask = self.startPanelSizeObservation()

        // 9. Start NotchActivityCoordinator.
        self.activityCoordinator.start()
    }

    /// Enables a provider at runtime: updates settings and starts the adapter.
    func enableProvider(_ id: ProviderID) async {
        do {
            try await self.providerRegistry.enableProvider(id)
            self.logger.info("Provider \(id.rawValue) enabled and started")
        } catch {
            self.logger.warning("Provider \(id.rawValue) failed to start: \(error)")
        }
    }

    /// Disables a provider at runtime: updates settings and stops the adapter.
    func disableProvider(_ id: ProviderID) async {
        await self.providerRegistry.disableProvider(id)
        self.logger.info("Provider \(id.rawValue) disabled and stopped")
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
    private var geometryObservationTask: Task<Void, Never>?
    private var panelSizeObservationTask: Task<Void, Never>?

    /// Creates the closure-based bridge connecting OIUI setup views to OIProviders.
    private func makeSetupActions() -> ProviderSetupActions {
        let coordinator = self.setupCoordinator
        let registry = self.providerRegistry
        return ProviderSetupActions(
            requirements: { providerID in
                await coordinator.setupRequirements(for: providerID)
            },
            install: { providerID, progressHandler in
                try await coordinator.install(provider: providerID) { progress in
                    let message = switch progress {
                    case .checkingPrerequisites: "Checking prerequisites…"
                    case let .creatingBackup(path): "Backing up \(path)…"
                    case .installingHooks: "Installing hooks…"
                    case .verifying: "Verifying setup…"
                    case .complete: "Complete"
                    case let .failed(error): "Failed: \(error)"
                    }
                    progressHandler(message)
                }
            },
            uninstall: { providerID in
                try await coordinator.uninstall(provider: providerID)
            },
            enableProvider: { providerID in
                try await registry.enableProvider(providerID)
            },
            disableProvider: { providerID in
                await registry.disableProvider(providerID)
            },
            isProviderRunning: { providerID in
                await registry.isRunning(providerID)
            },
        )
    }

    /// Spawns a task that keeps ``EventMonitors/geometry`` in sync with
    /// ``ScreenObserver/geometry`` via `withObservationTracking`.
    private func startGeometryObservation() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let state = Mutex<CheckedContinuation<Void, Never>?>(nil)

                await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        let shouldResumeNow = state.withLock { stored -> Bool in
                            if Task.isCancelled {
                                return true
                            }
                            stored = continuation
                            return false
                        }
                        if shouldResumeNow {
                            continuation.resume()
                            return
                        }

                        withObservationTracking {
                            _ = self.screenObserver.geometry
                        } onChange: {
                            let cont = state.withLock { stored -> CheckedContinuation<Void, Never>? in
                                let captured = stored
                                stored = nil
                                return captured
                            }
                            cont?.resume()
                        }
                    }
                } onCancel: {
                    let cont = state.withLock { stored -> CheckedContinuation<Void, Never>? in
                        let captured = stored
                        stored = nil
                        return captured
                    }
                    cont?.resume()
                }

                guard !Task.isCancelled else { break }
                self.eventMonitors.geometry = self.screenObserver.geometry
            }
        }
    }

    /// Spawns a task that observes ``NotchViewModel/status`` and
    /// ``NotchViewModel/openedSize``, forwarding the opened panel size
    /// to ``EventMonitors/panelSize`` so hover tracking uses the right bounds.
    private func startPanelSizeObservation() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let state = Mutex<CheckedContinuation<Void, Never>?>(nil)

                await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        let shouldResumeNow = state.withLock { stored -> Bool in
                            if Task.isCancelled {
                                return true
                            }
                            stored = continuation
                            return false
                        }
                        if shouldResumeNow {
                            continuation.resume()
                            return
                        }

                        withObservationTracking {
                            _ = self.viewModel.status
                            _ = self.viewModel.openedSize
                        } onChange: {
                            let cont = state.withLock { stored -> CheckedContinuation<Void, Never>? in
                                let captured = stored
                                stored = nil
                                return captured
                            }
                            cont?.resume()
                        }
                    }
                } onCancel: {
                    let cont = state.withLock { stored -> CheckedContinuation<Void, Never>? in
                        let captured = stored
                        stored = nil
                        return captured
                    }
                    cont?.resume()
                }

                guard !Task.isCancelled else { break }
                let status = self.viewModel.status
                self.eventMonitors.panelSize = status == .opened || status == .popping
                    ? self.viewModel.openedSize
                    : nil
            }
        }
    }
}
