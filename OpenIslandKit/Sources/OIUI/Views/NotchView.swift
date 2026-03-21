import OICore
import OIModules
import OIState
import OIWindow
public import SwiftUI

// MARK: - NotchView

//
// The closed-state notch width is computed by `ModuleLayoutEngine` in OIModules.
// `ModuleLayoutEngine.layout(modules:context:config:)` returns a `ModuleLayoutResult`
// whose `totalExpansionWidth` (= leftSideWidth + rightSideWidth) determines how far
// the notch extends beyond the device notch rect. Each side uses only the width its
// visible modules need (asymmetric layout). The `closedSize` used in this view must
// be derived from that same result so that the SwiftUI visual boundary matches the
// AppKit hit-test boundary set on `PassThroughHostingView` (OIWindow). Never compute
// closed-state width independently.
//
// Counterpart: see the matching contract comment in `PassThroughHostingView.swift` (OIWindow).

/// Root SwiftUI view for the notch overlay.
///
/// Renders a `NotchShape`-clipped container with a header row (always visible)
/// and a content area (visible when opened). The shape's corner radii and the
/// container size animate between closed and opened states using layered spring
/// curves.
public struct NotchView: View {
    // MARK: Lifecycle

    public init(
        viewModel: NotchViewModel,
        sessionMonitor: SessionMonitor,
        activityCoordinator: NotchActivityCoordinator? = nil,
        onCheckForUpdates: (() -> Void)? = nil,
        updateStatusContent: AnyView? = nil,
        setupActions: ProviderSetupActions? = nil,
    ) {
        self.viewModel = viewModel
        self.sessionMonitor = sessionMonitor
        self.activityCoordinator = activityCoordinator
        self.onCheckForUpdates = onCheckForUpdates
        self.updateStatusContent = updateStatusContent
        self.setupActions = setupActions
    }

    // MARK: Public

    public var body: some View {
        let isOpened = self.viewModel.status == .opened
        let isPopping = self.viewModel.status == .popping
        let size = isOpened ? self.viewModel.openedSize : self.closedSize

        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Horizontal padding in closed state keeps modules inward from the
                // clip shape's rounded corners (shapeEdgeMargin breathing room).
                NotchHeaderView(viewModel: self.viewModel, activityCoordinator: self.activityCoordinator)
                    .frame(height: isOpened ? 44 : self.closedSize.height)
                    .padding(.horizontal, isOpened ? 0 : ModuleLayoutEngine.shapeEdgeMargin)

                if isOpened {
                    self.notchContent
                        .transition(self.contentTransition)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .background(.black)
        .clipShape(
            NotchShape(
                topCornerRadius: isOpened ? 19 : 6,
                bottomCornerRadius: isOpened ? 24 : 14,
            ),
        )
        .background {
            // Shadow applied to a separate NotchShape behind the clipped content
            // so it follows the rounded contour. Placing .shadow() directly after
            // .clipShape() renders the shadow on the view's rectangular frame,
            // producing visible rectangular edge artifacts on hover.
            NotchShape(
                topCornerRadius: isOpened ? 19 : 6,
                bottomCornerRadius: isOpened ? 24 : 14,
            )
            .fill(.black)
            .shadow(
                color: self.shadowColor(isOpened: isOpened, isPopping: isPopping),
                radius: self.shadowRadius(isOpened: isOpened, isPopping: isPopping),
            )
        }
        .contentShape(
            NotchShape(
                topCornerRadius: isOpened ? 19 : 6,
                bottomCornerRadius: isOpened ? 24 : 14,
            ),
        )
        .scaleEffect(isPopping ? 1.02 : 1.0)
        .onHover { hovering in
            if self.reduceMotion {
                self.viewModel.setHovered(hovering)
            } else {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                    self.viewModel.setHovered(hovering)
                }
            }
        }
        .animation(self.reduceMotion ? .none : self.openCloseAnimation(isOpened: isOpened), value: isOpened)
        .animation(self.reduceMotion ? .none : .smooth(duration: 0.4), value: isPopping)
        .animation(self.reduceMotion ? .none : .smooth(duration: 0.3), value: self.viewModel.contentType.discriminator)
        .animation(self.reduceMotion ? .none : .smooth, value: self.viewModel.visibilityContext.isProcessing)
        .animation(self.reduceMotion ? .none : .smooth, value: self.viewModel.visibilityContext.hasPendingPermission)
        .animation(self.reduceMotion ? .none : .smooth, value: self.viewModel.visibilityContext.hasWaitingForInput)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isOpened ? "Open Island panel, expanded" : "Open Island panel, collapsed")
        // When closed with asymmetric module widths, shift the visual shape so
        // its internal notch gap stays aligned with the physical notch.
        .offset(x: isOpened ? 0 : self.closedNotchAlignmentOffset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Private

    @Environment(\.accessibilityReduceMotion) private var reduceMotion // swiftlint:disable:this attributes

    private var viewModel: NotchViewModel
    private var sessionMonitor: SessionMonitor
    private var activityCoordinator: NotchActivityCoordinator?
    private var onCheckForUpdates: (() -> Void)?
    private var updateStatusContent: AnyView?
    private var setupActions: ProviderSetupActions?

    /// The notch size when closed, derived from the device notch rect plus module expansion
    /// and shape edge margin.
    ///
    /// Width includes the device notch plus `totalExpansionWidth` from the layout engine
    /// plus `2 * shapeEdgeMargin` for clip-shape breathing room,
    /// honoring the hit-test / visual sync contract.
    private var closedSize: CGSize {
        let rect = self.viewModel.geometry.deviceNotchRect
        let layout = self.viewModel.moduleLayout
        return CGSize(
            width: rect.width + layout.totalExpansionWidth + 2 * ModuleLayoutEngine.shapeEdgeMargin,
            height: rect.height,
        )
    }

    /// Horizontal offset that keeps the closed-state notch gap aligned with the
    /// physical notch when left and right module widths differ.
    ///
    /// Without this offset the visual shape is centered on the screen, but the
    /// content inside is `[left modules][notch spacer][right modules]`. When the
    /// sides are asymmetric the notch spacer drifts from the physical notch by
    /// `(leftSideWidth − rightSideWidth) / 2`, potentially letting modules
    /// encroach into the hardware notch exclusion area.
    private var closedNotchAlignmentOffset: CGFloat {
        let layout = self.viewModel.moduleLayout
        return (layout.leftSideWidth - layout.rightSideWidth) / 2
    }

    // MARK: - Animations

    private var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.8, anchor: .top)
                .combined(with: .opacity)
                .animation(.smooth(duration: 0.35)),
            removal: .opacity.animation(.easeOut(duration: 0.15)),
        )
    }

    // MARK: - Content

    @ViewBuilder private var notchContent: some View {
        switch self.viewModel.contentType {
        case .instances:
            InstancesView(monitor: self.sessionMonitor, viewModel: self.viewModel)
        case let .chat(session):
            ChatView(session: session, monitor: self.sessionMonitor, viewModel: self.viewModel)
        case .menu:
            SettingsMenuView(
                viewModel: self.viewModel,
                onCheckForUpdates: self.onCheckForUpdates,
                updateStatusContent: self.updateStatusContent,
                setupActions: self.setupActions,
            )
        }
    }

    // MARK: - Shadow

    private func shadowColor(isOpened: Bool, isPopping: Bool) -> Color {
        if isOpened || isPopping {
            .black.opacity(0.7)
        } else if self.viewModel.isHovered {
            .black.opacity(0.3)
        } else {
            .clear
        }
    }

    private func shadowRadius(isOpened: Bool, isPopping: Bool) -> CGFloat {
        if isPopping {
            8
        } else if isOpened {
            6
        } else if self.viewModel.isHovered {
            3
        } else {
            0
        }
    }

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
        registry.register(SessionDotsModule())
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
            notchSize: CGSize(width: 224, height: 38),
            screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        )
    }
}
