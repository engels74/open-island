import OICore
import OIModules
import OIState
import OIWindow
package import SwiftUI

// MARK: - NotchView

//
// The closed-state notch width is computed by `ModuleLayoutEngine` in OIModules.
// `ModuleLayoutEngine.layout(modules:context:config:)` returns a `ModuleLayoutResult`
// whose `totalExpansionWidth` determines how far the notch extends beyond the
// device notch rect. The `closedSize` used in this view must be derived from that
// same result so that the SwiftUI visual boundary matches the AppKit hit-test
// boundary set on `PassThroughHostingView` (OIWindow). Never compute closed-state
// width independently.
//
// Counterpart: see the matching contract comment in `PassThroughHostingView.swift` (OIWindow).

/// Root SwiftUI view for the notch overlay.
///
/// Renders a `NotchShape`-clipped container with a header row (always visible)
/// and a content area (visible when opened). The shape's corner radii and the
/// container size animate between closed and opened states using layered spring
/// curves.
package struct NotchView: View {
    // MARK: Lifecycle

    package init(viewModel: NotchViewModel, sessionMonitor: SessionMonitor) {
        self.viewModel = viewModel
        self.sessionMonitor = sessionMonitor
    }

    // MARK: Package

    package var body: some View {
        let isOpened = self.viewModel.status == .opened
        let size = isOpened ? self.viewModel.openedSize : self.closedSize

        ZStack(alignment: .top) {
            // Background fill
            RoundedRectangle(cornerRadius: isOpened ? 24 : 14)
                .fill(.black)

            VStack(spacing: 0) {
                // Header — always visible
                NotchHeaderView(viewModel: self.viewModel)
                    .frame(height: isOpened ? 44 : self.closedSize.height)

                // Content — visible when opened
                if isOpened {
                    self.notchContent
                        .transition(self.contentTransition)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(
            NotchShape(
                topCornerRadius: isOpened ? 19 : 6,
                bottomCornerRadius: isOpened ? 24 : 14,
            ),
        )
        .shadow(color: .black.opacity(isOpened ? 0.35 : 0.15), radius: isOpened ? 20 : 4, y: isOpened ? 8 : 2)
        .animation(self.openCloseAnimation(isOpened: isOpened), value: isOpened)
        .animation(.smooth(duration: 0.3), value: self.viewModel.contentType.discriminator)
    }

    // MARK: Private

    private var viewModel: NotchViewModel
    private var sessionMonitor: SessionMonitor

    /// The notch size when closed, derived from the device notch rect plus module expansion.
    ///
    /// Width includes the device notch plus `totalExpansionWidth` from the layout engine,
    /// honoring the hit-test / visual sync contract.
    private var closedSize: CGSize {
        let rect = self.viewModel.geometry.deviceNotchRect
        let layout = self.viewModel.moduleLayout
        return CGSize(
            width: rect.width + layout.totalExpansionWidth,
            height: rect.height,
        )
    }

    // MARK: - Animations

    /// Content insertion/removal transition.
    private var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.95, anchor: .top).combined(with: .opacity),
            removal: .opacity.animation(.easeOut(duration: 0.15)),
        )
    }

    // MARK: - Content

    /// Switched content area displayed when the notch is opened.
    @ViewBuilder private var notchContent: some View {
        switch self.viewModel.contentType {
        case .instances:
            InstancesView(monitor: self.sessionMonitor, viewModel: self.viewModel)
        case let .chat(session):
            Text("Chat: \(session.projectName)")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .menu:
            Text("Settings Menu")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Spring animation for open/close, with distinct parameters per direction.
    private func openCloseAnimation(isOpened: Bool) -> Animation {
        if isOpened {
            .spring(response: 0.42, dampingFraction: 0.8)
        } else {
            .spring(response: 0.45, dampingFraction: 1.0)
        }
    }
}

// MARK: - NotchContentType + Discriminator

private extension NotchContentType {
    /// Hashable discriminator for animating content-type switches without
    /// requiring `NotchContentType` itself to be `Hashable`.
    var discriminator: Int {
        switch self {
        case .instances: 0
        case .chat: 1
        case .menu: 2
        }
    }
}

// MARK: - Previews

#Preview("Closed") {
    NotchView(viewModel: .previewClosed, sessionMonitor: .preview)
        .frame(width: 400, height: 100)
        .background(Color.gray.opacity(0.2))
}

#Preview("Opened — Instances") {
    NotchView(viewModel: .previewOpened(content: .instances), sessionMonitor: .preview)
        .frame(width: 800, height: 600)
        .background(Color.gray.opacity(0.2))
}

#Preview("Opened — Menu") {
    NotchView(viewModel: .previewOpened(content: .menu), sessionMonitor: .preview)
        .frame(width: 500, height: 500)
        .background(Color.gray.opacity(0.2))
}

// MARK: - Preview Helpers

@MainActor
private extension NotchViewModel {
    static var previewClosed: NotchViewModel {
        let registry = ModuleRegistry()
        registry.register(MascotModule(activeProviders: [.claude]))
        registry.register(ActivitySpinnerModule())
        registry.register(SessionDotsModule(providerCount: 2))
        let vm = NotchViewModel(geometry: .preview, registry: registry)
        vm.visibilityContext = ModuleVisibilityContext(
            isProcessing: true,
            activeProviders: [.claude],
        )
        return vm
    }

    static func previewOpened(content: NotchContentType = .instances) -> NotchViewModel {
        let registry = ModuleRegistry()
        registry.register(MascotModule(activeProviders: [.claude]))
        registry.register(ActivitySpinnerModule())
        let vm = NotchViewModel(geometry: .preview, registry: registry)
        vm.visibilityContext = ModuleVisibilityContext(
            isProcessing: true,
            activeProviders: [.claude],
        )
        vm.switchContent(content)
        vm.notchOpen(reason: .click)
        return vm
    }
}

@MainActor
private extension SessionMonitor {
    static var preview: SessionMonitor {
        SessionMonitor(store: SessionStore())
    }
}

private extension NotchGeometry {
    static var preview: NotchGeometry {
        NotchGeometry(
            notchSize: CGSize(width: 200, height: 32),
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        )
    }
}
