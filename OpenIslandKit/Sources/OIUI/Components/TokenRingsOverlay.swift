package import OICore
package import SwiftUI

// MARK: - TokenRingsOverlay

/// Detailed token usage view for the opened notch state.
///
/// Shows per-session token breakdown (prompt vs completion), weekly aggregate,
/// and quota percentage when available.
package struct TokenRingsOverlay: View {
    // MARK: Lifecycle

    package init(
        sessionTokens: [String: TokenUsageSnapshot],
        weeklyTokens: Int,
        quotaPercentage: Double?,
    ) {
        self.sessionTokens = sessionTokens
        self.weeklyTokens = weeklyTokens
        self.quotaPercentage = quotaPercentage
    }

    // MARK: Package

    package var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12))
                Text("Token Usage")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.9))

            HStack {
                Text("Total")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text(Self.formatCount(self.weeklyTokens))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
            }

            if let quota = self.quotaPercentage {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Quota")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text(String(format: "%.0f%%", quota))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Self.quotaColor(quota))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.white.opacity(0.1))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Self.quotaColor(quota))
                                .frame(width: geo.size.width * min(quota / 100.0, 1.0))
                        }
                    }
                    .frame(height: 4)
                }
            }

            if !self.sessionTokens.isEmpty {
                Divider()
                    .overlay(.white.opacity(0.1))

                ForEach(self.sortedSessions, id: \.key) { sessionID, snapshot in
                    SessionTokenRow(sessionID: sessionID, snapshot: snapshot)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.05)),
        )
    }

    // MARK: Fileprivate

    fileprivate static func formatCount(_ count: Int) -> String {
        switch count {
        case ..<1000:
            return "\(count) tokens"
        case ..<1_000_000:
            let thousands = Double(count) / 1000.0
            if thousands.truncatingRemainder(dividingBy: 1.0) == 0 {
                return "\(Int(thousands))K tokens"
            }
            return String(format: "%.1fK tokens", thousands)
        default:
            let millions = Double(count) / 1_000_000.0
            if millions.truncatingRemainder(dividingBy: 1.0) == 0 {
                return "\(Int(millions))M tokens"
            }
            return String(format: "%.1fM tokens", millions)
        }
    }

    // MARK: Private

    private let sessionTokens: [String: TokenUsageSnapshot]
    private let weeklyTokens: Int
    private let quotaPercentage: Double?

    private var sortedSessions: [(key: String, value: TokenUsageSnapshot)] {
        self.sessionTokens.sorted { $0.value.timestamp > $1.value.timestamp }
    }

    private static func quotaColor(_ percentage: Double) -> Color {
        if percentage > 90 {
            return .red.opacity(0.9)
        } else if percentage > 70 {
            return .yellow.opacity(0.8)
        }
        return .green.opacity(0.7)
    }
}

// MARK: - SessionTokenRow

private struct SessionTokenRow: View {
    // MARK: Internal

    let sessionID: String
    let snapshot: TokenUsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(self.truncatedID)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if let total = self.snapshot.totalTokens {
                    Text(TokenRingsOverlay.formatCount(total))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            HStack(spacing: 12) {
                if let prompt = self.snapshot.promptTokens {
                    Label(
                        title: {
                            Text("\(prompt)")
                                .font(.system(size: 9, design: .monospaced))
                        },
                        icon: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 8))
                        },
                    )
                    .foregroundStyle(.blue.opacity(0.6))
                }

                if let completion = self.snapshot.completionTokens {
                    Label(
                        title: {
                            Text("\(completion)")
                                .font(.system(size: 9, design: .monospaced))
                        },
                        icon: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 8))
                        },
                    )
                    .foregroundStyle(.green.opacity(0.6))
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    private var truncatedID: String {
        String(self.sessionID.prefix(8))
    }
}

// MARK: - Preview

#Preview("TokenRingsOverlay") {
    let now = Date()
    TokenRingsOverlay(
        sessionTokens: [
            "sess-abc12345": TokenUsageSnapshot(
                promptTokens: 3200,
                completionTokens: 1800,
                totalTokens: 5000,
                timestamp: now,
            ),
            "sess-def67890": TokenUsageSnapshot(
                promptTokens: 8500,
                completionTokens: 4200,
                totalTokens: 12700,
                timestamp: now.addingTimeInterval(-120),
            ),
        ],
        weeklyTokens: 17700,
        quotaPercentage: 42.0,
    )
    .frame(width: 280)
    .padding()
    .background(.black)
}
