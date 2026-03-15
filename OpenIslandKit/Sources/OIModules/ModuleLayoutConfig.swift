package import Foundation

// MARK: - ModuleLayoutEntry

/// A single module's persisted layout configuration.
package struct ModuleLayoutEntry: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    package init(moduleID: String, side: ModuleSide, order: Int, isHidden: Bool = false) {
        self.moduleID = moduleID
        self.side = side
        self.order = order
        self.isHidden = isHidden
    }

    // MARK: Package

    /// The module's unique identifier (matches `NotchModule.id`).
    package let moduleID: String

    /// Which side of the notch this module is placed on.
    package var side: ModuleSide

    /// Sort order within its side (lower values appear closer to the notch).
    package var order: Int

    /// Whether the user has hidden this module.
    package var isHidden: Bool
}

// MARK: - ModuleLayoutConfig

/// Persists user-customized module layout to `UserDefaults`.
///
/// On load, the config is reconciled against the live registry:
/// - Stale entries (modules no longer registered) are pruned.
/// - Newly registered modules are appended at their default positions.
package struct ModuleLayoutConfig: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    package init(entries: [ModuleLayoutEntry] = []) {
        self.entries = entries
    }

    // MARK: Package

    /// Per-module layout entries.
    package var entries: [ModuleLayoutEntry]

    /// Loads the config from `UserDefaults`, returning an empty config if none exists.
    package static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: defaultsKey),
              let config = try? JSONDecoder().decode(Self.self, from: data)
        else {
            return Self()
        }
        return config
    }

    /// Saves the config to `UserDefaults`.
    package func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// Reconciles the persisted config against currently registered modules.
    ///
    /// - Removes entries whose `moduleID` is not in `registeredModules`.
    /// - Adds entries for newly registered modules using their default side and order.
    package mutating func reconcile(with registeredModules: [any NotchModule]) {
        let registeredIDs = Set(registeredModules.map(\.id))

        // Prune stale entries
        self.entries.removeAll { !registeredIDs.contains($0.moduleID) }

        // Add new modules at their defaults
        let existingIDs = Set(entries.map(\.moduleID))
        for module in registeredModules where !existingIDs.contains(module.id) {
            entries.append(ModuleLayoutEntry(
                moduleID: module.id,
                side: module.defaultSide,
                order: module.defaultOrder,
            ))
        }
    }

    /// Returns the effective side for a module, falling back to the module's default.
    package func effectiveSide(for module: any NotchModule) -> ModuleSide {
        self.entries.first { $0.moduleID == module.id }?.side ?? module.defaultSide
    }

    /// Returns the effective order for a module, falling back to the module's default.
    package func effectiveOrder(for module: any NotchModule) -> Int {
        self.entries.first { $0.moduleID == module.id }?.order ?? module.defaultOrder
    }

    /// Whether a module is hidden by the user.
    package func isHidden(_ moduleID: String) -> Bool {
        self.entries.first { $0.moduleID == moduleID }?.isHidden ?? false
    }

    // MARK: Private

    private static let defaultsKey = "com.openisland.moduleLayout"
}
