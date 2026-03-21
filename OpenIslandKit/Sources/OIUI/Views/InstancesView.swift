import OICore
import OIState
import OIWindow
package import SwiftUI

// MARK: - InstancesView

/// List of active coding-agent sessions displayed in the opened notch panel.
///
/// Each row shows the provider icon, project name, phase indicator, and
/// elapsed time. Tapping a row switches the notch content to that session's
/// chat view via ``NotchViewModel/switchContent(_:)``.
package struct InstancesView: View {
    // MARK: Lifecycle

    package init(monitor: SessionMonitor, viewModel: NotchViewModel) {
        self.monitor = monitor
        self.viewModel = viewModel
    }

    // MARK: Package

    package var body: some View {
        Group {
            if self.monitor.instances.isEmpty {
                self.emptyState
            } else {
                self.sessionList
            }
        }
    }

    // MARK: Private

    private let monitor: SessionMonitor
    private let viewModel: NotchViewModel

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(self.monitor.instances) { session in
                    SessionRow(session: session)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            self.viewModel.switchContent(.chat(session))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(session.projectName), \(Self.accessibilityPhaseLabel(for: session.phase))")
                        .accessibilityHint("Opens the chat for this session")
                        .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No active sessions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No active sessions")
    }

    private static func accessibilityPhaseLabel(for phase: SessionPhase) -> String {
        switch phase {
        case .idle: "Idle"
        case .processing: "Active"
        case .waitingForInput: "Waiting for input"
        case .waitingForApproval: "Waiting for approval"
        case .compacting: "Compacting context"
        case .ended: "Ended"
        }
    }
}

// MARK: - SessionRow

/// A single row displaying summary information for an active session.
private struct SessionRow: View {
    // MARK: Internal

    let session: SessionState

    var body: some View {
        HStack(spacing: 10) {
            self.providerIcon
            Text(self.session.projectName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            self.phaseBadge
            self.elapsedTimeLabel
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    private var phaseLabel: String {
        switch self.session.phase {
        case .idle: "Idle"
        case .processing: "Active"
        case .waitingForInput: "Input"
        case .waitingForApproval: "Approval"
        case .compacting: "Compacting"
        case .ended: "Ended"
        }
    }

    private var phaseColor: Color {
        switch self.session.phase {
        case .idle: .gray
        case .processing: .blue
        case .waitingForInput: .yellow
        case .waitingForApproval: .orange
        case .compacting: .purple
        case .ended: .secondary
        }
    }

    private var formattedElapsed: String {
        let interval = Date.now.timeIntervalSince(self.session.createdAt)
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private var providerIcon: some View {
        Image(systemName: self.sfSymbol(for: self.session.providerID))
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .accessibilityLabel("\(self.session.providerID.rawValue) provider")
    }

    private var phaseBadge: some View {
        HStack(spacing: 4) {
            if self.session.phase == .compacting {
                ProgressView()
                    .controlSize(.mini)
                    .tint(.purple)
            }
            Text(self.phaseLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(self.phaseColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(self.phaseColor.opacity(0.15), in: Capsule())
        .accessibilityLabel(self.session.phase == .compacting ? "Context compaction in progress" : self.phaseLabel)
    }

    private var elapsedTimeLabel: some View {
        Text(self.formattedElapsed)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .frame(minWidth: 36, alignment: .trailing)
    }

    private func sfSymbol(for provider: ProviderID) -> String {
        switch provider {
        case .claude: "terminal.fill"
        case .codex: "diamond.fill"
        case .geminiCLI: "sparkles"
        case .openCode: "cpu"
        case .example: "play.circle"
        }
    }
}

// MARK: - Previews

private func previewGeometry() -> NotchGeometry {
    NotchGeometry(
        notchSize: CGSize(width: 224, height: 38),
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
    )
}

#Preview("With Sessions") {
    @Previewable @State var monitor = SessionMonitor(store: SessionStore())
    let viewModel = NotchViewModel(geometry: previewGeometry())

    InstancesView(monitor: monitor, viewModel: viewModel)
        .frame(width: 720, height: 480)
        .task { monitor.start() }
}

#Preview("Empty State") {
    let monitor = SessionMonitor(store: SessionStore())
    let viewModel = NotchViewModel(geometry: previewGeometry())

    InstancesView(monitor: monitor, viewModel: viewModel)
        .frame(width: 720, height: 480)
}
