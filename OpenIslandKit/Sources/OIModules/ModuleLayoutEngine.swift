package import Foundation

// MARK: - ModuleLayout

/// The computed layout for a single module within the closed-state notch.
package struct ModuleLayout: Sendable {
    /// The module's identifier (matches `NotchModule.id`).
    package let moduleID: String

    /// Which side of the notch this module is placed on.
    package let side: ModuleSide

    /// Horizontal offset from the outer edge of this module's side, in points.
    ///
    /// Measured inward from the side boundary: for left-side modules, this is the
    /// distance from the left edge of the expansion zone; for right-side modules,
    /// this is the distance from the right edge of the expansion zone.
    package let offsetFromEdge: CGFloat

    /// The module's width in points, as returned by `preferredWidth()`.
    package let width: CGFloat
}

// MARK: - ModuleLayoutResult

/// The complete layout result for the closed-state notch expansion.
///
/// This is the **single source of truth** for closed-state width. Both the AppKit
/// hit-test layer (`PassThroughHostingView`) and the SwiftUI visual layer
/// (`NotchView`) must consume this result to keep interaction bounds and visual
/// bounds in sync.
///
/// ## Layout geometry
///
/// ```
/// ◄── symmetricSideWidth ──►◄── device notch ──►◄── symmetricSideWidth ──►
/// ┌─────────────────────────┬──────────────────────┬─────────────────────────┐
/// │  outerInset │ mod │ sp │ mod │                  │ mod │ sp │ mod │ outerInset │
/// └─────────────────────────┴──────────────────────┴─────────────────────────┘
/// ◄──────────────────── totalExpansionWidth ──────────────────────────────────►
/// ```
///
/// - `symmetricSideWidth`: `max(leftNaturalWidth, rightNaturalWidth)`.
///   Both sides are padded to this width so the notch remains visually centered.
/// - `totalExpansionWidth`: `symmetricSideWidth × 2`. This is the amount the
///   closed-state notch extends *beyond* the device notch rect.
package struct ModuleLayoutResult: Sendable {
    /// Per-module positions, sorted by side then by display order.
    package let modules: [ModuleLayout]

    /// The width of each side after symmetry enforcement, in points.
    ///
    /// Equal to `max(leftNaturalWidth, rightNaturalWidth)`.
    package let symmetricSideWidth: CGFloat

    /// Total horizontal expansion beyond the device notch rect, in points.
    ///
    /// Equal to `symmetricSideWidth × 2`.
    package let totalExpansionWidth: CGFloat

    /// Natural (pre-symmetry) width of the left side, in points.
    package let leftNaturalWidth: CGFloat

    /// Natural (pre-symmetry) width of the right side, in points.
    package let rightNaturalWidth: CGFloat
}

// MARK: - ModuleLayoutEngine

/// Pure-computation engine that produces closed-state module layout from a list
/// of modules and the current visibility context.
///
/// ## Design contract
///
/// This engine is the **single source of truth** for the closed-state notch width.
/// No other component should independently compute module widths or positions.
/// Both `PassThroughHostingView` (AppKit hit-test boundary) and `NotchView`
/// (SwiftUI visual boundary) must derive their closed-state dimensions from the
/// `ModuleLayoutResult` produced here. See the contract comments in those files.
///
/// ## Layout algorithm
///
/// 1. Filter modules to those visible in the current context.
/// 2. Exclude user-hidden modules and partition by effective side/order
///    (when a `ModuleLayoutConfig` is provided), or fall back to
///    `defaultSide`/`defaultOrder`.
/// 3. Sort each side by effective order (ascending).
/// 4. Compute natural width per side: outer-edge inset (6pt) + sum of module
///    widths + inter-module spacing (8pt between adjacent modules).
/// 5. Enforce symmetry: `symmetricSideWidth = max(left, right)`.
/// 6. `totalExpansionWidth = symmetricSideWidth × 2`.
/// 7. Compute per-module offsets from the outer edge inward.
package enum ModuleLayoutEngine {
    // MARK: Package

    // MARK: - Constants

    /// Spacing between adjacent modules on the same side, in points.
    package static let interModuleSpacing: CGFloat = 8

    /// Inset from the outermost edge of the expansion zone to the first module, in points.
    package static let outerEdgeInset: CGFloat = 6

    // MARK: - Layout computation

    /// Computes the closed-state module layout.
    ///
    /// - Parameters:
    ///   - modules: All registered modules (visible and invisible).
    ///   - context: The current visibility context used to filter modules.
    ///   - config: Optional layout config for user-customized side/order/hidden
    ///     overrides. When provided, hidden modules are excluded and effective
    ///     side/order from the config are used instead of module defaults.
    /// - Returns: A `ModuleLayoutResult` with per-module positions and total width.
    ///   Returns a zero-width result when no modules are visible.
    package static func layout(
        modules: [any NotchModule],
        context: ModuleVisibilityContext,
        config: ModuleLayoutConfig? = nil,
    ) -> ModuleLayoutResult {
        let visible = modules.filter { $0.isVisible(context: context) }

        let leftModules: [any NotchModule]
        let rightModules: [any NotchModule]

        if let config {
            leftModules = visible
                .filter { !config.isHidden($0.id) && config.effectiveSide(for: $0) == .left }
                .sorted { config.effectiveOrder(for: $0) < config.effectiveOrder(for: $1) }

            rightModules = visible
                .filter { !config.isHidden($0.id) && config.effectiveSide(for: $0) == .right }
                .sorted { config.effectiveOrder(for: $0) < config.effectiveOrder(for: $1) }
        } else {
            leftModules = visible
                .filter { $0.defaultSide == .left }
                .sorted { $0.defaultOrder < $1.defaultOrder }

            rightModules = visible
                .filter { $0.defaultSide == .right }
                .sorted { $0.defaultOrder < $1.defaultOrder }
        }

        let (leftLayouts, leftNatural) = Self.computeSideLayouts(
            modules: leftModules,
            side: .left,
        )
        let (rightLayouts, rightNatural) = Self.computeSideLayouts(
            modules: rightModules,
            side: .right,
        )

        let symmetric = max(leftNatural, rightNatural)

        return ModuleLayoutResult(
            modules: leftLayouts + rightLayouts,
            symmetricSideWidth: symmetric,
            totalExpansionWidth: symmetric * 2,
            leftNaturalWidth: leftNatural,
            rightNaturalWidth: rightNatural,
        )
    }

    // MARK: Private

    // MARK: - Private helpers

    /// Computes layouts and natural width for one side.
    ///
    /// Natural width is `0` when there are no modules on this side.
    /// Otherwise: `outerEdgeInset + module₁.width + spacing + module₂.width + … + spacing + moduleₙ.width`.
    /// Note: no trailing inset — modules pack inward from the edge.
    private static func computeSideLayouts(
        modules: [any NotchModule],
        side: ModuleSide,
    ) -> (layouts: [ModuleLayout], naturalWidth: CGFloat) {
        guard !modules.isEmpty else {
            return ([], 0)
        }

        var layouts: [ModuleLayout] = []
        layouts.reserveCapacity(modules.count)

        var cursor = self.outerEdgeInset

        for (index, module) in modules.enumerated() {
            let width = module.preferredWidth()

            layouts.append(ModuleLayout(
                moduleID: module.id,
                side: side,
                offsetFromEdge: cursor,
                width: width,
            ))

            cursor += width
            if index < modules.count - 1 {
                cursor += self.interModuleSpacing
            }
        }

        return (layouts, cursor)
    }
}
