package import SwiftUI

// MARK: - ActivitySpinnerModule

/// Shows a small spinner when any provider session is actively processing.
///
/// Visible only when ``ModuleVisibilityContext/isProcessing`` is `true`.
package struct ActivitySpinnerModule: NotchModule {
    // MARK: Lifecycle

    package init() {}

    // MARK: Package

    package let id = "activity-spinner"
    package let defaultSide = ModuleSide.right
    package let defaultOrder = 0
    package let showInExpandedHeader = false

    package func isVisible(context: ModuleVisibilityContext) -> Bool {
        context.isProcessing
    }

    package func preferredWidth() -> CGFloat {
        20
    }

    @MainActor
    package func makeBody(context: ModuleRenderContext) -> AnyView {
        AnyView(self.body(context: context))
    }

    // MARK: Private

    @MainActor
    private func body(context: ModuleRenderContext) -> some View {
        ProgressView()
            .controlSize(.mini)
            .tint(context.accentColor)
    }
}

// MARK: - Preview

#Preview("ActivitySpinnerModule") {
    _ActivitySpinnerPreview()
        .padding()
        .background(.black)
}

// MARK: - _ActivitySpinnerPreview

@MainActor
private struct _ActivitySpinnerPreview: View {
    // MARK: Internal

    var body: some View {
        ActivitySpinnerModule()
            .makeBody(context: ModuleRenderContext(animationNamespace: self.ns))
    }

    // MARK: Private

    @Namespace private var ns
}
