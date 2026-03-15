package import SwiftUI

// MARK: - SessionDotsModule

/// Shows a dot per active provider session, up to a maximum of 5.
///
/// When more than 5 providers are active, displays a count badge instead.
/// Visible whenever there are active providers. The rendered count is derived
/// from ``ModuleRenderContext/activeProviderCount`` — the same source of truth
/// used by ``isVisible(context:)`` — to prevent visibility/rendering drift.
package struct SessionDotsModule: NotchModule {
    // MARK: Lifecycle

    package init() {}

    // MARK: Package

    package let id = "session-dots"
    package let defaultSide = ModuleSide.right
    package let defaultOrder = 2
    package let showInExpandedHeader = false

    package func isVisible(context: ModuleVisibilityContext) -> Bool {
        !context.activeProviders.isEmpty
    }

    package func preferredWidth() -> CGFloat {
        30
    }

    @MainActor
    package func makeBody(context: ModuleRenderContext) -> AnyView {
        AnyView(self.body(context: context))
    }

    // MARK: Private

    private static let maxDots = 5

    @MainActor
    @ViewBuilder
    private func body(context: ModuleRenderContext) -> some View {
        let count = context.activeProviderCount

        if count <= Self.maxDots {
            HStack(spacing: 3) {
                ForEach(0 ..< count, id: \.self) { _ in
                    Circle()
                        .fill(context.accentColor)
                        .frame(width: 4, height: 4)
                }
            }
        } else {
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(context.accentColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule()
                        .fill(context.accentColor.opacity(0.2)),
                )
        }
    }
}

// MARK: - Preview

#Preview("SessionDotsModule") {
    HStack(spacing: 16) {
        _SessionDotsPreviewItem(count: 1, label: "1")
        _SessionDotsPreviewItem(count: 3, label: "3")
        _SessionDotsPreviewItem(count: 5, label: "5")
        _SessionDotsPreviewItem(count: 8, label: "8")
    }
    .padding()
    .background(.black)
}

// MARK: - _SessionDotsPreviewItem

@MainActor
private struct _SessionDotsPreviewItem: View {
    // MARK: Internal

    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            SessionDotsModule()
                .makeBody(context: ModuleRenderContext(
                    animationNamespace: self.ns,
                    activeProviderCount: self.count,
                ))
            Text(self.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    @Namespace private var ns
}
