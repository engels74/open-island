package import SwiftUI

// MARK: - PermissionIndicatorModule

/// Shows an exclamation mark indicator when a provider session has a pending
/// permission request.
///
/// Visible only when ``ModuleVisibilityContext/hasPendingPermission`` is `true`.
package struct PermissionIndicatorModule: NotchModule {
    // MARK: Lifecycle

    package init() {}

    // MARK: Package

    package let id = "permission-indicator"
    package let defaultSide = ModuleSide.left
    package let defaultOrder = 1
    package let showInExpandedHeader = false

    package func isVisible(context: ModuleVisibilityContext) -> Bool {
        context.hasPendingPermission
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
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.yellow)
            .symbolRenderingMode(.hierarchical)
    }
}

// MARK: - Preview

#Preview("PermissionIndicatorModule") {
    _PermissionIndicatorPreview()
        .padding()
        .background(.black)
}

// MARK: - _PermissionIndicatorPreview

@MainActor
private struct _PermissionIndicatorPreview: View {
    // MARK: Internal

    var body: some View {
        PermissionIndicatorModule()
            .makeBody(context: ModuleRenderContext(animationNamespace: self.ns))
    }

    // MARK: Private

    @Namespace private var ns
}
