package import SwiftUI

// MARK: - SessionDotsModule

/// Shows a dot per active provider session, up to a maximum of 5.
///
/// When more than 5 providers are active, displays a count badge instead.
/// Visible whenever there are active providers.
package struct SessionDotsModule: NotchModule {
    // MARK: Lifecycle

    /// - Parameter providerCount: Number of active providers to display.
    package init(providerCount: Int = 0) {
        self.providerCount = providerCount
    }

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

    /// Number of active providers, injected at construction.
    private let providerCount: Int

    @MainActor
    @ViewBuilder
    private func body(context: ModuleRenderContext) -> some View {
        // The module receives render context but needs provider count.
        // We store the count at construction time for the body to use.
        if self.providerCount <= Self.maxDots {
            HStack(spacing: 3) {
                ForEach(0 ..< self.providerCount, id: \.self) { _ in
                    Circle()
                        .fill(context.accentColor)
                        .frame(width: 4, height: 4)
                }
            }
        } else {
            Text("\(self.providerCount)")
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
            SessionDotsModule(providerCount: self.count)
                .makeBody(context: ModuleRenderContext(animationNamespace: self.ns))
            Text(self.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    @Namespace private var ns
}
