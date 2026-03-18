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
        CyclingSpinnerView(color: context.accentColor)
    }
}

// MARK: - CyclingSpinnerView

@MainActor
package struct CyclingSpinnerView: View {
    // MARK: Lifecycle

    package init(color: Color) {
        self.color = color
    }

    // MARK: Package

    package let color: Color

    package var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.15) % self.symbols.count
            Text(self.symbols[phase])
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(self.color)
                .frame(width: 12, alignment: .center)
        }
    }

    // MARK: Private

    private let symbols = ["·", "✢", "✳", "∗", "✻", "✽"]
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
