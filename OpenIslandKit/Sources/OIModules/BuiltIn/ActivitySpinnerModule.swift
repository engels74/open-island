public import SwiftUI

// MARK: - ActivitySpinnerModule

/// Shows a small spinner when any provider session is actively processing.
///
/// Visible only when ``ModuleVisibilityContext/isProcessing`` is `true`.
public struct ActivitySpinnerModule: NotchModule {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public let id = "activity-spinner"
    public let defaultSide = ModuleSide.right
    public let defaultOrder = 0
    public let showInExpandedHeader = false

    public func isVisible(context: ModuleVisibilityContext) -> Bool {
        context.isProcessing
    }

    public func preferredWidth() -> CGFloat {
        20
    }

    @MainActor
    public func makeBody(context: ModuleRenderContext) -> AnyView {
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
