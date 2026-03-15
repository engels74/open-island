package import OICore
package import SwiftUI

// MARK: - ModuleSide

/// Which side of the notch a module appears on.
package enum ModuleSide: String, Sendable, Codable, Hashable, BitwiseCopyable {
    case left
    case right
}

// MARK: - ModuleVisibilityContext

/// Aggregated session state passed to modules for visibility decisions.
///
/// The layout engine constructs this from current session data without
/// requiring modules to reach into global singletons, keeping the module
/// system testable in isolation.
package struct ModuleVisibilityContext: Sendable, Equatable {
    // MARK: Lifecycle

    package init(
        isProcessing: Bool = false,
        hasPendingPermission: Bool = false,
        hasWaitingForInput: Bool = false,
        activeProviders: Set<ProviderID> = [],
        aggregateProviderState: [ProviderID: ProviderActivitySummary] = [:],
    ) {
        self.isProcessing = isProcessing
        self.hasPendingPermission = hasPendingPermission
        self.hasWaitingForInput = hasWaitingForInput
        self.activeProviders = activeProviders
        self.aggregateProviderState = aggregateProviderState
    }

    // MARK: Package

    /// Whether any active session is currently processing.
    package let isProcessing: Bool

    /// Whether any active session has a pending permission request.
    package let hasPendingPermission: Bool

    /// Whether any active session is waiting for user input.
    package let hasWaitingForInput: Bool

    /// Set of providers with active sessions.
    package let activeProviders: Set<ProviderID>

    /// Per-provider activity summaries for provider-aware module decisions.
    package let aggregateProviderState: [ProviderID: ProviderActivitySummary]
}

// MARK: - ModuleRenderContext

/// Context passed to modules when rendering their view body.
///
/// Isolated to `@MainActor` because it carries `Namespace.ID` (a SwiftUI type
/// that is not `Sendable`) and is only used within `@ViewBuilder` rendering
/// contexts on the main thread.
@MainActor
package struct ModuleRenderContext {
    // MARK: Lifecycle

    package init(
        animationNamespace: Namespace.ID,
        accentColor: Color = .white,
        isHighlighted: Bool = false,
        activeProviderCount: Int = 0,
    ) {
        self.animationNamespace = animationNamespace
        self.accentColor = accentColor
        self.isHighlighted = isHighlighted
        self.activeProviderCount = activeProviderCount
    }

    // MARK: Package

    /// Animation namespace for matched geometry effects across modules.
    package let animationNamespace: Namespace.ID

    /// Accent color derived from the active provider or system theme.
    package let accentColor: Color

    /// Whether this module's area is visually highlighted (e.g., during hover).
    package let isHighlighted: Bool

    /// Number of active providers, derived from ``ModuleVisibilityContext/activeProviders``.
    ///
    /// Modules that display provider-count-dependent content should use this
    /// value rather than injecting a separate count, keeping visibility and
    /// rendering in sync with the same source of truth.
    package let activeProviderCount: Int
}

// MARK: - NotchModule

/// A self-contained UI component displayed in the closed notch header.
///
/// Modules declare their preferred side, ordering, and visibility criteria.
/// The ``ModuleLayoutEngine`` queries these properties to compute the closed-state
/// layout, and ``ModuleRegistry`` stores modules as `any NotchModule`.
///
/// ## `makeBody` return type — `AnyView` rationale
///
/// The protocol requires `makeBody` to return `AnyView` rather than using an
/// associated type or `some View`. This is because modules are stored
/// heterogeneously in `ModuleRegistry` as `any NotchModule`. While Swift's
/// SE-0352 (implicitly opened existentials) can open the concrete type at the
/// call site, the opened type erases to `any View` which cannot satisfy
/// `some View` in a `@ViewBuilder` context — the compiler emits
/// "type 'any View' cannot conform to 'View'".
///
/// Concrete implementations should build their view hierarchy using
/// `@ViewBuilder` internally and wrap the result with `AnyView`:
///
/// ```swift
/// func makeBody(context: ModuleRenderContext) -> AnyView {
///     AnyView(myViewBody(context: context))
/// }
///
/// @ViewBuilder
/// private func myViewBody(context: ModuleRenderContext) -> some View { ... }
/// ```
package protocol NotchModule: Identifiable where ID == String {
    /// Unique identifier for this module.
    var id: String { get }

    /// Preferred side of the notch for this module.
    var defaultSide: ModuleSide { get }

    /// Sort order within its side (lower values are laid out first from the outer edge inward).
    var defaultOrder: Int { get }

    /// Whether this module should also appear in the expanded header.
    var showInExpandedHeader: Bool { get }

    /// Whether this module should be visible given the current session state.
    func isVisible(context: ModuleVisibilityContext) -> Bool

    /// Preferred width in points for this module's content area.
    func preferredWidth() -> CGFloat

    /// Builds the module's view content.
    @MainActor
    func makeBody(context: ModuleRenderContext) -> AnyView
}
