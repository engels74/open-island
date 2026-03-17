import SwiftUI

// MARK: - NotchUpdateView

/// Compact update status view displayed in the notch overlay's About section.
///
/// Shows update availability, download progress, and install actions.
struct NotchUpdateView: View {
    // MARK: Internal

    var updateManager: UpdateManager

    var body: some View {
        switch self.updateManager.state.phase {
        case .idle,
             .checking:
            EmptyView()

        case .available:
            self.availableView

        case .downloading:
            self.downloadingView

        case .extracting:
            self.extractingView

        case .readyToInstall:
            self.readyToInstallView

        case .installing:
            self.installingView
        }
    }

    // MARK: Private

    private var availableView: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 12))
                Text("Update Available: v\(self.updateManager.state.availableVersion ?? "?")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
            }

            HStack(spacing: 8) {
                Button("Install") {
                    self.updateManager.acceptUpdate()
                }
                .controlSize(.small)

                Button("Later") {
                    self.updateManager.dismissUpdate()
                }
                .controlSize(.small)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var downloadingView: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Downloading update...")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(self.updateManager.state.downloadProgress * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: self.updateManager.state.downloadProgress)
                .progressViewStyle(.linear)
        }
    }

    private var extractingView: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Extracting update...")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            ProgressView(value: self.updateManager.state.extractionProgress)
                .progressViewStyle(.linear)
        }
    }

    private var readyToInstallView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12))
            Text("Ready to install")
                .font(.system(size: 11))
                .foregroundStyle(.white)
            Spacer()
            Button("Restart") {
                self.updateManager.installAndRelaunch()
            }
            .controlSize(.small)
        }
    }

    private var installingView: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text("Installing...")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
