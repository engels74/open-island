package import SwiftUI
import UniformTypeIdentifiers

// MARK: - ModulePlacement

/// Represents where a module can be placed in the layout.
private enum ModulePlacement: String, CaseIterable, Sendable {
    case left
    case right
    case hidden

    // MARK: Internal

    var title: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .hidden: "Hidden"
        }
    }

    var systemImage: String {
        switch self {
        case .left: "arrow.left.square"
        case .right: "arrow.right.square"
        case .hidden: "eye.slash"
        }
    }
}

// MARK: - DraggedModule

/// Transfer representation for drag-and-drop.
private struct DraggedModule: Codable, Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plainText)
    }

    let moduleID: String
}

// MARK: - ModuleLayoutSettingsView

/// A settings view for arranging notch modules via drag-and-drop.
///
/// Presents three columns — **Left**, **Right**, and **Hidden** — where users can
/// drag modules between columns to configure the closed-state notch layout.
/// Changes are immediately persisted to ``ModuleLayoutConfig`` via the registry.
package struct ModuleLayoutSettingsView: View {
    // MARK: Lifecycle

    package init(registry: ModuleRegistry) {
        self.registry = registry
    }

    // MARK: Package

    package var body: some View {
        VStack(spacing: 16) {
            self.header

            HStack(alignment: .top, spacing: 12) {
                self.columnView(for: .left)
                self.columnView(for: .right)
                self.columnView(for: .hidden)
            }
        }
        .padding(16)
    }

    // MARK: Private

    @State private var dropTargetPlacement: ModulePlacement?

    private let registry: ModuleRegistry

    private var header: some View {
        HStack {
            Text("Module Layout")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button("Reset to Defaults") {
                self.registry.resetLayoutToDefaults()
            }
            .font(.system(size: 11))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func columnView(for placement: ModulePlacement) -> some View {
        let modules = self.modules(for: placement)
        let isTargeted = self.dropTargetPlacement == placement

        VStack(spacing: 0) {
            // Column header
            Label(placement.title, systemImage: placement.systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

            Divider()

            // Module list or empty state
            VStack(spacing: 4) {
                if modules.isEmpty {
                    self.emptyState(for: placement)
                } else {
                    ForEach(modules, id: \.id) { module in
                        self.moduleRow(module)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(isTargeted ? 1 : 0.5))
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.blue.opacity(0.6), lineWidth: 2)
            }
        }
        .dropDestination(for: DraggedModule.self) { items, _ in
            guard let item = items.first else { return false }
            self.moveModule(item.moduleID, to: placement)
            return true
        } isTargeted: { targeted in
            self.dropTargetPlacement = targeted ? placement : nil
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    private func moduleRow(_ module: any NotchModule) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Text(module.id)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.background.opacity(0.8)),
        )
        .draggable(DraggedModule(moduleID: module.id))
    }

    private func emptyState(for placement: ModulePlacement) -> some View {
        Text(placement == .hidden ? "Drop here to hide" : "Drop modules here")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .multilineTextAlignment(.center)
    }

    // MARK: - Data

    private func modules(for placement: ModulePlacement) -> [any NotchModule] {
        let config = self.registry.layoutConfig

        return self.registry.allModules
            .filter { module in
                switch placement {
                case .hidden:
                    config.isHidden(module.id)
                case .left:
                    !config.isHidden(module.id) && config.effectiveSide(for: module) == .left
                case .right:
                    !config.isHidden(module.id) && config.effectiveSide(for: module) == .right
                }
            }
            .sorted {
                let lhs = config.effectiveOrder(for: $0)
                let rhs = config.effectiveOrder(for: $1)
                return lhs != rhs ? lhs < rhs : $0.id < $1.id
            }
    }

    private func moveModule(_ moduleID: String, to placement: ModulePlacement) {
        var config = self.registry.layoutConfig

        let index: Int
        if let existing = config.entries.firstIndex(where: { $0.moduleID == moduleID }) {
            index = existing
        } else {
            // Entry missing (layout not yet reconciled). Create one using the
            // module's defaults so the drag-and-drop still works.
            guard let module = self.registry.allModules.first(where: { $0.id == moduleID }) else {
                return
            }
            config.entries.append(ModuleLayoutEntry(
                moduleID: moduleID,
                side: module.defaultSide,
                order: module.defaultOrder,
            ))
            index = config.entries.count - 1
        }

        switch placement {
        case .hidden:
            config.entries[index].isHidden = true
        case .left:
            config.entries[index].isHidden = false
            config.entries[index].side = .left
            config.entries[index].order = self.nextOrder(in: config, for: .left)
        case .right:
            config.entries[index].isHidden = false
            config.entries[index].side = .right
            config.entries[index].order = self.nextOrder(in: config, for: .right)
        }

        self.registry.updateLayoutConfig(config)
    }

    private func nextOrder(in config: ModuleLayoutConfig, for side: ModuleSide) -> Int {
        let maxOrder = config.entries
            .filter { $0.side == side && !$0.isHidden }
            .map(\.order)
            .max() ?? -1
        return maxOrder + 1
    }
}

// MARK: - Preview

#Preview("Module Layout Settings") {
    ModuleLayoutSettingsView(registry: {
        let registry = ModuleRegistry()

        // Create simple preview modules
        struct PreviewModule: NotchModule {
            let id: String
            let defaultSide: ModuleSide
            let defaultOrder: Int
            let showInExpandedHeader = false
            func isVisible(context: ModuleVisibilityContext) -> Bool {
                true
            }

            func preferredWidth() -> CGFloat {
                24
            }

            @MainActor
            func makeBody(context: ModuleRenderContext) -> AnyView {
                AnyView(Circle().fill(.white).frame(width: 8, height: 8))
            }
        }

        registry.register(PreviewModule(id: "activity", defaultSide: .left, defaultOrder: 0))
        registry.register(PreviewModule(id: "timer", defaultSide: .left, defaultOrder: 1))
        registry.register(PreviewModule(id: "mascot", defaultSide: .right, defaultOrder: 0))
        registry.register(PreviewModule(id: "dots", defaultSide: .right, defaultOrder: 1))
        registry.register(PreviewModule(id: "permission", defaultSide: .right, defaultOrder: 2))

        var config = ModuleLayoutConfig()
        config.reconcile(with: registry.allModules)
        registry.updateLayoutConfig(config)

        return registry
    }())
        .frame(width: 460, height: 300)
        .background(.black)
        .preferredColorScheme(.dark)
}
