import OICore
import OIModules
import OIWindow
package import SwiftUI

// MARK: - NotchHeaderView

/// Header bar for the notch overlay that adapts between closed and opened states.
///
/// In closed state, renders real modules from the registry: left modules + notch
/// spacer + right modules. In opened state, shows navigation controls, an activity
/// indicator, and a title that adapts to the current content type. Modules with
/// `showInExpandedHeader == true` also appear in the opened header.
package struct NotchHeaderView: View {
    // MARK: Lifecycle

    package init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
    }

    // MARK: Package

    package var body: some View {
        Group {
            switch self.viewModel.status {
            case .closed,
                 .popping:
                self.closedHeader
                    .frame(height: self.viewModel.geometry.deviceNotchRect.height)
            case .opened:
                self.openedHeader
                    .frame(height: Self.openedHeight)
            }
        }
        .animation(self.reduceMotion ? .none : .snappy(duration: 0.25), value: self.viewModel.status)
    }

    // MARK: Private

    private static let openedHeight: CGFloat = 44

    @Environment(\.accessibilityReduceMotion) private var reduceMotion // swiftlint:disable:this attributes

    @Namespace private var headerNamespace

    private let viewModel: NotchViewModel

    private var title: String {
        switch self.viewModel.contentType {
        case .instances:
            "Open Island"
        case let .chat(session):
            session.projectName
        case .menu:
            "Settings"
        }
    }

    /// The render context passed to modules when building their views.
    private var renderContext: ModuleRenderContext {
        ModuleRenderContext(
            animationNamespace: self.headerNamespace,
            activeProviderCount: self.viewModel.visibilityContext.activeProviders.count,
        )
    }

    /// Visible left-side modules for the closed state, sorted by effective order.
    private var closedLeftModules: [any NotchModule] {
        self.viewModel.registry.effectiveModules(for: .left)
            .filter { $0.isVisible(context: self.viewModel.visibilityContext) }
    }

    /// Visible right-side modules for the closed state, sorted by effective order.
    private var closedRightModules: [any NotchModule] {
        self.viewModel.registry.effectiveModules(for: .right)
            .filter { $0.isVisible(context: self.viewModel.visibilityContext) }
    }

    /// Modules that declare `showInExpandedHeader == true`, visible in the opened header.
    private var expandedHeaderModules: [any NotchModule] {
        self.viewModel.registry.allModules
            .filter { $0.showInExpandedHeader && $0.isVisible(context: self.viewModel.visibilityContext) }
            .sorted { $0.defaultOrder < $1.defaultOrder }
    }

    // MARK: - Closed State

    private var closedHeader: some View {
        HStack(spacing: 0) {
            // Left-side modules — framed to the symmetric width so the
            // visual boundary matches the layout engine's width contract.
            self.closedModuleRow(modules: self.closedLeftModules, side: .left)
                .frame(
                    width: self.viewModel.moduleLayout.symmetricSideWidth,
                    alignment: .leading,
                )

            // Notch spacer — fills the device notch width in the center
            Spacer(minLength: 0)
                .frame(width: self.viewModel.geometry.deviceNotchRect.width)

            // Right-side modules — mirrored symmetric width.
            self.closedModuleRow(modules: self.closedRightModules, side: .right)
                .frame(
                    width: self.viewModel.moduleLayout.symmetricSideWidth,
                    alignment: .trailing,
                )
        }
    }

    // MARK: - Opened State

    private var openedHeader: some View {
        HStack(spacing: 12) {
            self.leadingControls
            Spacer()
            self.titleText
            Spacer()
            self.trailingControls
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var leadingControls: some View {
        switch self.viewModel.contentType {
        case .instances:
            // Close button — chevron down to dismiss
            Button {
                self.viewModel.notchClose()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close panel")
            .accessibilityHint("Collapses the Open Island panel")
        case .chat,
             .menu:
            // Back button — returns to instances
            Button {
                self.viewModel.switchContent(.instances)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to sessions")
            .accessibilityHint("Returns to the session list")
        }
    }

    private var titleText: some View {
        Text(self.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private var trailingControls: some View {
        HStack(spacing: 8) {
            // Expanded-header modules (if any)
            ForEach(self.expandedHeaderModules, id: \.id) { module in
                module.makeBody(context: self.renderContext)
            }

            self.activityIndicator

            // Settings button
            Button {
                self.viewModel.switchContent(.menu)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens the settings menu")
        }
    }

    private var activityIndicator: some View {
        ProgressView()
            .controlSize(.small)
            .matchedGeometryEffect(id: "activity", in: self.headerNamespace)
            .accessibilityLabel("Activity in progress")
    }

    /// Renders a horizontal row of modules with the layout engine's spacing.
    ///
    /// The outer-edge inset is applied only on the side facing away from the
    /// device notch, matching the layout engine's width model (which does not
    /// include a trailing/inner inset).
    @ViewBuilder
    private func closedModuleRow(modules: [any NotchModule], side: ModuleSide) -> some View {
        if modules.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: ModuleLayoutEngine.interModuleSpacing) {
                ForEach(modules, id: \.id) { module in
                    module.makeBody(context: self.renderContext)
                        .frame(width: module.preferredWidth())
                }
            }
            .padding(side == .left ? .leading : .trailing, ModuleLayoutEngine.outerEdgeInset)
        }
    }
}

// MARK: - Previews

/// Creates a preview-ready registry with common built-in modules.
@MainActor
private func previewRegistry() -> ModuleRegistry {
    let registry = ModuleRegistry()
    registry.register(MascotModule(activeProviders: [.claude]))
    registry.register(PermissionIndicatorModule())
    registry.register(ActivitySpinnerModule())
    registry.register(ReadyCheckmarkModule())
    registry.register(SessionDotsModule())
    registry.register(TimerModule(startDate: Date().addingTimeInterval(-125)))
    return registry
}

private let previewGeometry = NotchGeometry(
    notchSize: CGSize(width: 200, height: 36),
    screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
)

#Preview("Opened — Instances") {
    NotchHeaderView(
        viewModel: {
            let vm = NotchViewModel(geometry: previewGeometry, registry: previewRegistry())
            vm.visibilityContext = ModuleVisibilityContext(
                isProcessing: true,
                activeProviders: [.claude],
            )
            vm.notchOpen(reason: .click)
            return vm
        }(),
    )
    .frame(width: 720)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Opened — Chat") {
    NotchHeaderView(
        viewModel: {
            let vm = NotchViewModel(geometry: previewGeometry, registry: previewRegistry())
            vm.visibilityContext = ModuleVisibilityContext(
                isProcessing: true,
                activeProviders: [.claude],
            )
            vm.notchOpen(reason: .click)
            vm.switchContent(.chat(SessionState(
                id: "preview-1",
                providerID: .claude,
                phase: .processing,
                projectName: "MyProject",
                cwd: "/Users/dev/MyProject",
                createdAt: .now,
                lastActivityAt: .now,
            )))
            return vm
        }(),
    )
    .frame(width: 720)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Opened — Settings") {
    NotchHeaderView(
        viewModel: {
            let vm = NotchViewModel(geometry: previewGeometry, registry: previewRegistry())
            vm.notchOpen(reason: .click)
            vm.switchContent(.menu)
            return vm
        }(),
    )
    .frame(width: 420)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Closed — With Modules") {
    NotchHeaderView(
        viewModel: {
            let vm = NotchViewModel(geometry: previewGeometry, registry: previewRegistry())
            vm.visibilityContext = ModuleVisibilityContext(
                isProcessing: true,
                activeProviders: [.claude],
            )
            return vm
        }(),
    )
    .frame(width: 400)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Closed — Empty") {
    NotchHeaderView(
        viewModel: NotchViewModel(geometry: previewGeometry),
    )
    .frame(width: 200)
    .background(.black)
    .preferredColorScheme(.dark)
}
