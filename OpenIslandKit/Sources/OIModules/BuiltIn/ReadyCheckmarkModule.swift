public import SwiftUI

// MARK: - ReadyCheckmarkModule

/// Shows a checkmark icon when a provider session has completed work and is
/// waiting for user input.
///
/// Visible only when ``ModuleVisibilityContext/hasWaitingForInput`` is `true`,
/// indicating the agent finished a turn and is awaiting the next prompt.
public struct ReadyCheckmarkModule: NotchModule {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public let id = "ready-checkmark"
    public let defaultSide = ModuleSide.right
    public let defaultOrder = 1
    public let showInExpandedHeader = false

    public func isVisible(context: ModuleVisibilityContext) -> Bool {
        context.hasWaitingForInput
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
