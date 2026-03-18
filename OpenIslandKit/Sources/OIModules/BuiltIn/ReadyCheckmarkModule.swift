public import SwiftUI

// MARK: - ReadyCheckmarkModule

/// Shows a checkmark icon when at least one provider is active and none are
/// currently processing.
///
/// Visible when NOT processing AND at least one active provider exists.
public struct ReadyCheckmarkModule: NotchModule {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public let id = "ready-checkmark"
    public let defaultSide = ModuleSide.right
    public let defaultOrder = 1
    public let showInExpandedHeader = false

    public func isVisible(context: ModuleVisibilityContext) -> Bool {
        !context.isProcessing && !context.activeProviders.isEmpty
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
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.green)
            .symbolRenderingMode(.hierarchical)
    }
}

// MARK: - Preview

#Preview("ReadyCheckmarkModule") {
    _ReadyCheckmarkPreview()
        .padding()
        .background(.black)
}

// MARK: - _ReadyCheckmarkPreview

@MainActor
private struct _ReadyCheckmarkPreview: View {
    // MARK: Internal

    var body: some View {
        ReadyCheckmarkModule()
            .makeBody(context: ModuleRenderContext(animationNamespace: self.ns))
    }

    // MARK: Private

    @Namespace private var ns
}
