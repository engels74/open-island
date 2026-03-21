package import OICore
import OIState
package import SwiftUI

// MARK: - ApprovalBarView

/// Permission approval bar shown at the bottom of ``ChatView`` when a session
/// is in the `.waitingForApproval` phase.
///
/// Displays the tool name, an optional risk-level badge, and Approve / Deny /
/// Always Allow action buttons. Slides in from the bottom with a combined
/// move + opacity transition.
package struct ApprovalBarView: View {
    // MARK: Lifecycle

    package init(context: PermissionContext, sessionID: String, monitor: SessionMonitor) {
        self.context = context
        self.sessionID = sessionID
        self.monitor = monitor
    }

    // MARK: Package

    package var body: some View {
        VStack(spacing: 8) {
            Divider()
                .overlay(.white.opacity(self.contrast == .increased ? 0.3 : 0.1))

            HStack(spacing: 10) {
                self.summaryLabel

                Spacer(minLength: 8)

                self.actionButtons
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Permission request: \(self.context.displaySummary)")
    }

    // MARK: Private

    @Environment(\.colorSchemeContrast) private var contrast // swiftlint:disable:this attributes

    private let context: PermissionContext
    private let sessionID: String
    private let monitor: SessionMonitor

    // MARK: - Summary Label

    private var summaryLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 14))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(self.context.displaySummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let risk = self.context.risk {
                    RiskBadge(risk: risk)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool: \(self.context.displaySummary)\(self.context.risk.map { ", risk level \($0)" } ?? "")")
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button {
                self.monitor.denyPermission(sessionID: self.sessionID, requestID: self.context.toolUseID)
            } label: {
                Text("Deny")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.red.opacity(0.7), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Deny")
            .accessibilityHint("Denies the tool permission request")

            Button {
                self.monitor.approvePermission(sessionID: self.sessionID, requestID: self.context.toolUseID)
            } label: {
                Text("Always Allow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Always Allow")
            .accessibilityHint("Approves this and future requests for this tool")

            Button {
                self.monitor.approvePermission(sessionID: self.sessionID, requestID: self.context.toolUseID)
            } label: {
                Text("Approve")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.green.opacity(0.7), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Approve")
            .accessibilityHint("Approves the tool permission request")
        }
    }
}

// MARK: - RiskBadge

/// Color-coded badge indicating the risk level of a permission request.
private struct RiskBadge: View {
    // MARK: Internal

    let risk: PermissionRisk

    var body: some View {
        Text(self.label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(self.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(self.color.opacity(0.15), in: Capsule())
            .accessibilityLabel("Risk level: \(self.label.lowercased())")
    }

    // MARK: Private

    private var label: String {
        switch self.risk {
        case .low: "LOW"
        case .medium: "MEDIUM"
        case .high: "HIGH"
        }
    }

    private var color: Color {
        switch self.risk {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }
}

// MARK: - Previews

#Preview("Approval Bar — High Risk") {
    ApprovalBarView(
        context: PermissionContext(
            toolUseID: "req-1",
            toolName: "Bash",
            toolInput: .object(["command": .string("rm -rf node_modules")]),
            timestamp: .now,
            risk: .high,
        ),
        sessionID: "session-1",
        monitor: SessionMonitor(store: SessionStore()),
    )
    .frame(width: 720)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Approval Bar — Medium Risk") {
    ApprovalBarView(
        context: PermissionContext(
            toolUseID: "req-2",
            toolName: "Write",
            toolInput: .object(["path": .string("/Users/dev/project/config.json")]),
            timestamp: .now,
            risk: .medium,
        ),
        sessionID: "session-1",
        monitor: SessionMonitor(store: SessionStore()),
    )
    .frame(width: 720)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Approval Bar — Low Risk") {
    ApprovalBarView(
        context: PermissionContext(
            toolUseID: "req-3",
            toolName: "Read",
            toolInput: .object(["path": .string("Package.swift")]),
            timestamp: .now,
            risk: .low,
        ),
        sessionID: "session-1",
        monitor: SessionMonitor(store: SessionStore()),
    )
    .frame(width: 720)
    .background(.black)
    .preferredColorScheme(.dark)
}

#Preview("Approval Bar — No Risk") {
    ApprovalBarView(
        context: PermissionContext(
            toolUseID: "req-4",
            toolName: "Glob",
            timestamp: .now,
        ),
        sessionID: "session-1",
        monitor: SessionMonitor(store: SessionStore()),
    )
    .frame(width: 720)
    .background(.black)
    .preferredColorScheme(.dark)
}
