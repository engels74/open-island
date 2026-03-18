public import Observation
import Synchronization

// MARK: - WindowControllerHandle

/// An opaque handle to a window controller created by the factory.
///
/// This protocol enables dependency inversion: `WindowManager` lives in OIWindow
/// and cannot import OIUI (where `NotchWindowController` is defined). The OIUI
/// layer provides a factory that returns a handle conforming to this protocol.
@MainActor
public protocol WindowControllerHandle: AnyObject {
    /// Updates the window controller with new notch geometry.
    func updateGeometry(_ geometry: NotchGeometry)

    /// Tears down the window and releases resources.
    func tearDown()
}

// MARK: - WindowManager

/// Creates and manages the notch window lifecycle.
///
/// `WindowManager` is the entry point that the app delegate or SwiftUI `App` calls
/// to set up the notch panel. It subscribes to `ScreenObserver` for geometry updates
/// and tears down / recreates the window controller when screens change.
///
/// The actual window controller type is injected via a factory closure, keeping this
/// module free of OIUI dependencies.
@MainActor
@Observable
public final class WindowManager {
    // MARK: Lifecycle

    /// Creates a `WindowManager` with the given screen observer and window controller factory.
    ///
    /// - Parameters:
    ///   - screenObserver: The observer that publishes screen geometry changes.
    ///   - controllerFactory: A closure that creates a `WindowControllerHandle` for a given geometry.
    ///     The OIUI layer provides this, typically wrapping `NotchWindowController`.
    public init(
        screenObserver: ScreenObserver,
        controllerFactory: @escaping @MainActor (NotchGeometry) -> any WindowControllerHandle,
    ) {
        self.screenObserver = screenObserver
        self.controllerFactory = controllerFactory
    }

    deinit {
        observationTask?.cancel()
        // activeController teardown is handled by stop() — callers must call stop()
        // before releasing the WindowManager. deinit cannot call MainActor-isolated
        // methods on the protocol.
    }

    // MARK: Public

    /// Whether the window is currently active (a notch screen is available and the controller is live).
    public var isActive: Bool {
        self.activeController != nil
    }

    /// Sets up the initial window and begins observing screen changes.
    ///
    /// Call this once from the app delegate or SwiftUI `App.init`.
    public func start() {
        // Create window for the initial geometry, if available.
        if let geometry = self.screenObserver.geometry {
            self.createController(for: geometry)
        }

        // Observe geometry changes from the screen observer.
        self.observationTask = Task { [weak self] in
            guard let self else { return }
            // withObservationTracking re-invokes the closure on each change.
            // We loop to keep observing after each update.
            while !Task.isCancelled {
                // Mutex-protected continuation ensures exactly one resume across
                // the observation onChange callback and the cancellation handler.
                let state = Mutex<CheckedContinuation<NotchGeometry?, Never>?>(nil)

                let currentGeometry = await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        // Store the continuation; if the task was already cancelled
                        // before we get here, resume immediately.
                        let shouldResumeNow = state.withLock { stored -> Bool in
                            if Task.isCancelled {
                                return true
                            }
                            stored = continuation
                            return false
                        }
                        if shouldResumeNow {
                            continuation.resume(returning: nil)
                            return
                        }

                        withObservationTracking {
                            _ = self.screenObserver.geometry
                        } onChange: {
                            Task { @MainActor [weak self] in
                                let cont = state.withLock { stored -> CheckedContinuation<NotchGeometry?, Never>? in
                                    let captured = stored
                                    stored = nil
                                    return captured
                                }
                                guard let cont else { return }
                                cont.resume(returning: self?.screenObserver.geometry)
                            }
                        }
                    }
                } onCancel: {
                    let cont = state.withLock { stored -> CheckedContinuation<NotchGeometry?, Never>? in
                        let captured = stored
                        stored = nil
                        return captured
                    }
                    cont?.resume(returning: nil)
                }
                guard !Task.isCancelled else { break }
                self.handleGeometryChange(currentGeometry)
            }
        }
    }

    /// Tears down the current window and stops observing.
    public func stop() {
        self.observationTask?.cancel()
        self.observationTask = nil
        self.destroyController()
    }

    // MARK: Private

    @ObservationIgnored private let screenObserver: ScreenObserver

    @ObservationIgnored private let controllerFactory: @MainActor (NotchGeometry) -> any WindowControllerHandle

    @ObservationIgnored private var activeController: (any WindowControllerHandle)?

    @ObservationIgnored private var observationTask: Task<Void, Never>?

    @ObservationIgnored private var currentGeometry: NotchGeometry?

    private func handleGeometryChange(_ newGeometry: NotchGeometry?) {
        guard newGeometry != self.currentGeometry else { return }

        if let newGeometry {
            if self.activeController != nil {
                // Screen reconfigured (e.g., resolution change) — update in place.
                self.activeController?.updateGeometry(newGeometry)
            } else {
                // Notch screen appeared (e.g., lid opened) — create controller.
                self.createController(for: newGeometry)
            }
        } else {
            // Notch screen gone (e.g., lid closed, external-only) — tear down.
            self.destroyController()
        }

        self.currentGeometry = newGeometry
    }

    private func createController(for geometry: NotchGeometry) {
        self.destroyController()
        self.activeController = self.controllerFactory(geometry)
        self.currentGeometry = geometry
    }

    private func destroyController() {
        self.activeController?.tearDown()
        self.activeController = nil
        self.currentGeometry = nil
    }
}
