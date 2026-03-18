public import OICore
public import SwiftUI

// MARK: - MascotModule

/// Shows a provider-appropriate SF Symbol icon in the closed-state notch.
///
/// When a single provider is active, displays that provider's icon.
/// When multiple providers are active or none are specified, displays a generic icon.
/// Always visible regardless of session state.
public struct MascotModule: NotchModule {
    // MARK: Lifecycle

    public init(activeProviders: Set<ProviderID> = []) {
        self.activeProviders = activeProviders
    }

    // MARK: Public

    public let id = "mascot"
    public let defaultSide = ModuleSide.left
    public let defaultOrder = 0
    public let showInExpandedHeader = false

    public func isVisible(context: ModuleVisibilityContext) -> Bool {
        true
    }

    public func preferredWidth() -> CGFloat {
        20
    }

    @MainActor
    public func makeBody(context: ModuleRenderContext) -> AnyView {
        AnyView(self.body(context: context))
    }

    // MARK: Private

    /// The set of currently active providers, used for icon resolution.
    ///
    /// Injected by the integration layer that constructs modules each layout pass.
    private let activeProviders: Set<ProviderID>

    /// The SF Symbol icon name based on active providers.
    ///
    /// - Single provider: provider-specific icon
    /// - Multiple or zero providers: generic fallback
    private var iconName: String {
        guard self.activeProviders.count == 1,
              let provider = activeProviders.first
        else {
            return "questionmark.circle"
        }
        return switch provider {
        case .claude: "brain.head.profile"
        case .codex: "diamond"
        case .geminiCLI: "sparkles"
        case .openCode: "circle.hexagongrid"
        case .example: "play.circle"
        }
    }

    @MainActor
    private func body(context: ModuleRenderContext) -> some View {
        Image(systemName: self.iconName)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(context.accentColor)
            .symbolEffect(.pulse, isActive: context.isHighlighted)
            .shadow(
                color: context.isHighlighted ? context.accentColor.opacity(0.3) : .clear,
                radius: 2,
            )
    }
}

// MARK: - Preview

#Preview("MascotModule") {
    HStack(spacing: 16) {
        _MascotPreviewItem(providers: [], label: "Generic")
        _MascotPreviewItem(providers: [.claude], label: "Claude")
        _MascotPreviewItem(providers: [.codex], label: "Codex")
        _MascotPreviewItem(providers: [.geminiCLI], label: "Gemini")
        _MascotPreviewItem(providers: [.openCode], label: "OpenCode")
        _MascotPreviewItem(providers: [.claude, .codex], label: "Multi")
    }
    .padding()
    .background(.black)
}

// MARK: - _MascotPreviewItem

@MainActor
private struct _MascotPreviewItem: View {
    // MARK: Internal

    let providers: Set<ProviderID>
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            MascotModule(activeProviders: self.providers)
                .makeBody(context: ModuleRenderContext(animationNamespace: self.ns))
            Text(self.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Private

    @Namespace private var ns
}
