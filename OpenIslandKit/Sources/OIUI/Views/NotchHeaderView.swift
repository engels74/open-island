import OICore
import OIWindow
package import SwiftUI

// MARK: - NotchHeaderView

/// Header bar for the notch overlay that adapts between closed and opened states.
///
/// In closed state, shows a minimal centered capsule indicator.
/// In opened state, shows navigation controls, a mascot icon, activity indicator,
/// and a title that adapts to the current content type.
package struct NotchHeaderView: View {
    // MARK: Lifecycle

    package init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
    }

    // MARK: Package

    package var body: some View {
        Group {
            switch self.viewModel.status {
            case .closed,
                 .popping:
                self.closedHeader
                    .frame(height: self.viewModel.geometry.deviceNotchRect.height)
            case .opened:
                self.openedHeader
                    .frame(height: Self.openedHeight)
            }
        }
        .animation(.snappy(duration: 0.25), value: self.viewModel.status)
    }

    // MARK: Private

    private static let openedHeight: CGFloat = 44

    @Namespace private var headerNamespace

    private let viewModel: NotchViewModel

    private var title: String {
        switch self.viewModel.contentType {
        case .instances:
            "Open Island"
        case let .chat(session):
            session.projectName
        case .menu:
            "Settings"
        }
    }

    // MARK: - Closed State

    private var closedHeader: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 32, height: 4)
                .matchedGeometryEffect(id: "activity", in: self.headerNamespace)
            Spacer()
        }
    }

    // MARK: - Opened State

    private var openedHeader: some View {
        HStack(spacing: 12) {
            self.leadingControls
            Spacer()
            self.titleText
            Spacer()
            self.trailingControls
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private var leadingControls: some View {
        switch self.viewModel.contentType {
        case .instances:
            // Close button — chevron down to dismiss
            Button {
                self.viewModel.notchClose()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .chat,
             .menu:
            // Back button — returns to instances
            Button {
                self.viewModel.switchContent(.instances)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var titleText: some View {
        Text(self.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private var trailingControls: some View {
        HStack(spacing: 8) {
            self.activityIndicator

            // Mascot icon placeholder
            Image(systemName: "circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)

            // Settings button
            Button {
                self.viewModel.switchContent(.menu)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var activityIndicator: some View {
        ProgressView()
            .controlSize(.small)
            .matchedGeometryEffect(id: "activity", in: self.headerNamespace)
    }
}

// MARK: - Previews

#Preview("Opened — Instances") {
    NotchHeaderView(
        viewModel: {
            let vm = NotchViewModel(
                geometry: NotchGeometry(
                    notchSize: CGSize(width: 200, height: 36),
                    screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                ),
            )
            vm.notchOpen(reason: .click)
            return vm
        }(),
    )
    .frame(width: 720)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Opened — Chat") {
    NotchHeaderView(
        viewModel: {
            let vm = NotchViewModel(
                geometry: NotchGeometry(
                    notchSize: CGSize(width: 200, height: 36),
                    screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                ),
            )
            vm.notchOpen(reason: .click)
            vm.switchContent(.chat(SessionState(
                id: "preview-1",
                providerID: .claude,
                phase: .processing,
                projectName: "MyProject",
                cwd: "/Users/dev/MyProject",
                createdAt: .now,
                lastActivityAt: .now,
            )))
            return vm
        }(),
    )
    .frame(width: 720)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Opened — Settings") {
    NotchHeaderView(
        viewModel: {
            let vm = NotchViewModel(
                geometry: NotchGeometry(
                    notchSize: CGSize(width: 200, height: 36),
                    screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                ),
            )
            vm.notchOpen(reason: .click)
            vm.switchContent(.menu)
            return vm
        }(),
    )
    .frame(width: 420)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Closed") {
    NotchHeaderView(
        viewModel: NotchViewModel(
            geometry: NotchGeometry(
                notchSize: CGSize(width: 200, height: 36),
                screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
            ),
        ),
    )
    .frame(width: 200)
    .background(.black)
    .preferredColorScheme(.dark)
}
