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
            onClickOutside: { event in
                vm.notchClose()
                Self.repostClick(for: event)
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
                activityCoordinator: self.activityCoordinator,
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

        // 7. Keep EventMonitors geometry in sync with ScreenObserver.
        self.geometryObservationTask = self.startGeometryObservation()

        // 8. Wire panel size so EventMonitors knows the opened panel bounds.
        self.panelSizeObservationTask = self.startPanelSizeObservation()

        // 9. Start NotchActivityCoordinator.
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
    private var geometryObservationTask: Task<Void, Never>?
    private var panelSizeObservationTask: Task<Void, Never>?

    /// Re-posts a mouse click for click-outside dismissal so the click reaches
    /// whatever is behind the notch panel (e.g. a menu bar item).
    ///
    /// Preserves the original event type (left/right), modifier flags, and click
    /// count. Mirrors the `CGEvent` pattern in `NotchPanel.repostMouseEvent()`.
    private static func repostClick(for event: NSEvent) {
        // Use the event's own CGEvent location rather than NSEvent.mouseLocation.
        // NSEvent.mouseLocation queries the *current* cursor position, which could
        // differ from the triggering event's position if the mouse moves between
        // event receipt and repost. CGEvent.location gives the recorded event
        // position directly in CG coordinates (top-left origin) — no conversion needed.
        guard let cgPoint = event.cgEvent?.location else { return }

        let cgDownType: CGEventType
        let cgUpType: CGEventType
        let mouseButton: CGMouseButton

        switch event.type {
        case .rightMouseDown:
            cgDownType = .rightMouseDown
            cgUpType = .rightMouseUp
            mouseButton = .right
        default:
            cgDownType = .leftMouseDown
            cgUpType = .leftMouseUp
            mouseButton = .left
        }

        guard let mouseDown = CGEvent(
            mouseEventSource: nil,
            mouseType: cgDownType,
            mouseCursorPosition: cgPoint,
            mouseButton: mouseButton,
        ),
            let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: cgUpType,
                mouseCursorPosition: cgPoint,
                mouseButton: mouseButton,
            )
        else { return }

        mouseDown.flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        mouseDown.setIntegerValueField(.mouseEventClickState, value: Int64(event.clickCount))
        mouseUp.flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
        mouseUp.setIntegerValueField(.mouseEventClickState, value: Int64(event.clickCount))

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
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
