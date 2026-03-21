public import SwiftUI

// MARK: - TimerModule

/// Shows elapsed time since the earliest active session started.
///
/// Always visible when there are active providers. Reads
/// ``ModuleRenderContext/earliestSessionStart`` to display a live
/// `mm:ss` or `h:mm:ss` formatted duration via `Text(_:style: .timer)`.
public struct TimerModule: NotchModule {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public let id = "timer"
    public let defaultSide = ModuleSide.right
    public let defaultOrder = 3
    public let showInExpandedHeader = false

    public func isVisible(context: ModuleVisibilityContext) -> Bool {
        !context.activeProviders.isEmpty
    }

    public func preferredWidth() -> CGFloat {
        40
    }

    @MainActor
    public func makeBody(context: ModuleRenderContext) -> AnyView {
        AnyView(self.body(context: context))
    }

    // MARK: Private

    @MainActor
    @ViewBuilder
    private func body(context: ModuleRenderContext) -> some View {
        if let startDate = context.earliestSessionStart {
            Text(startDate, style: .timer)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(context.accentColor.opacity(0.8))
                .monospacedDigit()
        } else {
            Text("0:00")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(context.accentColor.opacity(0.5))
                .monospacedDigit()
        }
    }
}

// MARK: - Preview

#Preview("TimerModule") {
    HStack(spacing: 16) {
        _TimerPreviewItem(startDate: nil, label: "No session")
        _TimerPreviewItem(startDate: Date().addingTimeInterval(-65), label: "1m 5s ago")
        _TimerPreviewItem(startDate: Date().addingTimeInterval(-3661), label: "~1h ago")
    }
    .padding()
    .background(.black)
}

// MARK: - _TimerPreviewItem

@MainActor
private struct _TimerPreviewItem: View {
    // MARK: Internal

    let startDate: Date?
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            TimerModule()
                .makeBody(context: ModuleRenderContext(
                    animationNamespace: self.ns,
                    earliestSessionStart: self.startDate,
                ))
            Text(self.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    @Namespace private var ns
}
