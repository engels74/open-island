package import Foundation
import Observation
package import OICore

// MARK: - ModuleRegistry

/// Central registry holding all notch modules for the closed-state UI.
///
/// Modules are registered dynamically at runtime via ``register(_:)``.
/// Views query modules filtered by side and sorted by display order.
@Observable
@MainActor
package final class ModuleRegistry {
    // MARK: Lifecycle

    package init() {}

    // MARK: Package

    /// All registered modules in insertion order.
    package private(set) var allModules: [any NotchModule] = []

    /// Persisted layout configuration for module arrangement.
    package private(set) var layoutConfig = ModuleLayoutConfig()

    /// Register a module for display in the closed-state notch.
    ///
    /// Duplicate registrations (matching ``NotchModule/id``) are ignored.
    package func register(_ module: any NotchModule) {
        guard !self.allModules.contains(where: { $0.id == module.id }) else { return }
        self.allModules.append(module)
    }

    /// Loads persisted layout config and reconciles it against registered modules.
    ///
    /// Call this after all modules have been registered. Prunes stale entries
    /// for modules no longer in the registry and adds entries for newly
    /// registered modules at their default positions.
    package func applyPersistedLayout(from defaults: UserDefaults = .standard) {
        self.layoutConfig = ModuleLayoutConfig.load(from: defaults)
        self.layoutConfig.reconcile(with: self.allModules)
        self.layoutConfig.save(to: defaults)
    }

    /// Returns modules for a given side, sorted by the effective order from
    /// the persisted layout config. Hidden modules are excluded.
    package func effectiveModules(for side: ModuleSide) -> [any NotchModule] {
        self.allModules
            .filter { !self.layoutConfig.isHidden($0.id) }
            .filter { self.layoutConfig.effectiveSide(for: $0) == side }
            .sorted {
                let lhs = self.layoutConfig.effectiveOrder(for: $0)
                let rhs = self.layoutConfig.effectiveOrder(for: $1)
                return lhs != rhs ? lhs < rhs : $0.id < $1.id
            }
    }

    /// Returns modules assigned to the given side, sorted by ``NotchModule/defaultOrder``.
    package func modules(for side: ModuleSide) -> [any NotchModule] {
        self.allModules
            .filter { $0.defaultSide == side }
            .sorted {
                $0.defaultOrder != $1.defaultOrder ? $0.defaultOrder < $1.defaultOrder : $0.id < $1.id
            }
    }

    /// Replaces the layout config and persists to `UserDefaults`.
    package func updateLayoutConfig(_ config: ModuleLayoutConfig, saveTo defaults: UserDefaults = .standard) {
        self.layoutConfig = config
        self.layoutConfig.save(to: defaults)
    }

    /// Resets the layout config to factory defaults based on registered modules.
    package func resetLayoutToDefaults(saveTo defaults: UserDefaults = .standard) {
        var config = ModuleLayoutConfig()
        config.reconcile(with: self.allModules)
        self.layoutConfig = config
        self.layoutConfig.save(to: defaults)
    }
}
