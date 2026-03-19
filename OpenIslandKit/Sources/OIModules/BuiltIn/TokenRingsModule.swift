package import SwiftUI

// MARK: - TokenRingsModule

/// Shows a compact token usage ring in the closed notch header.
///
/// Visible whenever there are active providers. Displays a small circular
/// arc representing the fraction of tokens used relative to the total session
/// activity. When ``totalTokens`` is zero and ``quotaFraction`` is `nil`,
/// renders an empty background track.
package struct TokenRingsModule: NotchModule {
    // MARK: Lifecycle

    /// - Parameters:
    ///   - totalTokens: Total tokens used in the current session aggregate.
    ///   - quotaFraction: Optional quota utilisation as 0.0–1.0. When `nil`,
    ///     the ring shows a fixed partial arc indicating "data available, no quota".
    package init(totalTokens: Int = 0, quotaFraction: Double? = nil) {
        self.totalTokens = totalTokens
        self.quotaFraction = quotaFraction
    }

    // MARK: Package

    package let id = "tokenRings"
    package let defaultSide = ModuleSide.right
    package let defaultOrder = 4
    package let showInExpandedHeader = false

    package func isVisible(context: ModuleVisibilityContext) -> Bool {
        !context.activeProviders.isEmpty
    }

    package func preferredWidth() -> CGFloat {
        22
    }

    @MainActor
    package func makeBody(context: ModuleRenderContext) -> AnyView {
        AnyView(self.body(context: context))
    }

    // MARK: Private

    private let totalTokens: Int
    private let quotaFraction: Double?

    private var arcFraction: Double {
        if let quota = quotaFraction {
            return min(max(quota, 0), 1.0)
        }
        // No quota: show a subtle partial arc to indicate token data exists
        return self.totalTokens > 0 ? 0.3 : 0
    }

    private var compactLabel: String {
        switch self.totalTokens {
        case ..<1000:
            return "\(self.totalTokens)"
        case ..<1_000_000:
            let thousands = Double(totalTokens) / 1000.0
            return String(format: "%.0fK", thousands)
        default:
            let millions = Double(totalTokens) / 1_000_000.0
            return String(format: "%.0fM", millions)
        }
    }

    @MainActor
    private func body(context: ModuleRenderContext) -> some View {
        ZStack {
            // Background track
            Circle()
                .stroke(
                    context.accentColor.opacity(0.15),
                    lineWidth: 2,
                )

            // Usage arc
            Circle()
                .trim(from: 0, to: self.arcFraction)
                .stroke(
                    self.arcColor(accent: context.accentColor),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round),
                )
                .rotationEffect(.degrees(-90))

            // Token count label (only when large enough to read)
            if self.totalTokens > 0 {
                Text(self.compactLabel)
                    .font(.system(size: 6, weight: .semibold, design: .monospaced))
                    .foregroundStyle(context.accentColor.opacity(0.7))
            }
        }
        .frame(width: 18, height: 18)
    }

    private func arcColor(accent: Color) -> Color {
        guard let quota = quotaFraction else {
            return accent.opacity(0.6)
        }
        if quota > 0.9 {
            return .red.opacity(0.9)
        } else if quota > 0.7 {
            return .yellow.opacity(0.8)
        }
        return accent.opacity(0.7)
    }
}

// MARK: - Preview

#Preview("TokenRingsModule") {
    HStack(spacing: 16) {
        _TokenRingPreviewItem(tokens: 0, quota: nil, label: "No data")
        _TokenRingPreviewItem(tokens: 1250, quota: nil, label: "1.3K no quota")
        _TokenRingPreviewItem(tokens: 45000, quota: 0.45, label: "45% used")
        _TokenRingPreviewItem(tokens: 85000, quota: 0.85, label: "85% used")
        _TokenRingPreviewItem(tokens: 95000, quota: 0.95, label: "95% used")
    }
    .padding()
    .background(.black)
}

// MARK: - _TokenRingPreviewItem

@MainActor
private struct _TokenRingPreviewItem: View {
    // MARK: Internal

    let tokens: Int
    let quota: Double?
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            TokenRingsModule(totalTokens: self.tokens, quotaFraction: self.quota)
                .makeBody(context: ModuleRenderContext(animationNamespace: self.ns))
            Text(self.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    @Namespace private var ns
}
