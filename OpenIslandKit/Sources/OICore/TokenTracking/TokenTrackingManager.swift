package import Foundation
import Observation

// MARK: - TokenTrackingManager

/// Aggregates per-session token usage and optional provider quota data.
///
/// Observe `sessionTokens`, `weeklyTokens`, or `quotaPercentage` from SwiftUI
/// views — only properties that are actually read trigger re-renders.
@Observable
@MainActor
package final class TokenTrackingManager {
    // MARK: Lifecycle

    package init(quotaService: (any QuotaService)? = nil) {
        self.quotaService = quotaService
    }

    // MARK: Package

    /// Per-session token snapshots keyed by session ID.
    package private(set) var sessionTokens: [String: TokenUsageSnapshot] = [:]

    /// Weekly aggregate token count (sum of all sessions' `totalTokens`).
    package private(set) var weeklyTokens = 0

    /// Quota utilisation as a percentage (0–100). `nil` when no quota data is
    /// available.
    package private(set) var quotaPercentage: Double?

    /// The latest quota snapshot, if any.
    package private(set) var latestQuota: QuotaSnapshot?

    /// Whether any token data is available for display.
    package var hasTokenData: Bool {
        !self.sessionTokens.isEmpty
    }

    /// Update token usage for a single session.
    package func updateSession(_ sessionID: String, usage: TokenUsageSnapshot) {
        self.sessionTokens[sessionID] = usage
        self.recalculateWeeklyTotal()
    }

    /// Bulk-update all session token data from a list of session states.
    package func updateFromSessions(_ sessions: [SessionTokenInfo]) {
        var changed = false
        for info in sessions {
            if let usage = info.tokenUsage {
                if self.sessionTokens[info.id] != usage {
                    self.sessionTokens[info.id] = usage
                    changed = true
                }
            } else if self.sessionTokens[info.id] != nil {
                self.sessionTokens.removeValue(forKey: info.id)
                changed = true
            }
        }
        let activeIDs = Set(sessions.map(\.id))
        let staleKeys = self.sessionTokens.keys.filter { !activeIDs.contains($0) }
        for key in staleKeys {
            self.sessionTokens.removeValue(forKey: key)
            changed = true
        }
        if changed {
            self.recalculateWeeklyTotal()
        }
    }

    /// Refresh quota data from the quota service, if one is configured.
    package func refreshQuota() async {
        guard let quotaService else { return }
        do {
            let snapshot = try await quotaService.fetchCurrentUsage()
            self.latestQuota = snapshot
            if let fraction = snapshot.utilizationFraction {
                self.quotaPercentage = fraction * 100.0
            } else {
                self.quotaPercentage = nil
            }
        } catch {
            // Quota fetch failures are non-fatal — keep showing stale data.
        }
    }

    package func removeSession(_ sessionID: String) {
        if self.sessionTokens.removeValue(forKey: sessionID) != nil {
            self.recalculateWeeklyTotal()
        }
    }

    // MARK: Private

    private let quotaService: (any QuotaService)?

    private func recalculateWeeklyTotal() {
        self.weeklyTokens = self.sessionTokens.values.compactMap(\.totalTokens).reduce(0, +)
    }
}

// MARK: - SessionTokenInfo

/// Minimal session info needed by ``TokenTrackingManager/updateFromSessions(_:)``.
///
/// This avoids coupling the manager to the full `SessionState` type.
package struct SessionTokenInfo: Sendable {
    // MARK: Lifecycle

    package init(id: String, tokenUsage: TokenUsageSnapshot?) {
        self.id = id
        self.tokenUsage = tokenUsage
    }

    // MARK: Package

    package let id: String
    package let tokenUsage: TokenUsageSnapshot?
}

// MARK: - Formatting Helpers

package extension TokenTrackingManager {
    /// Format a token count for compact display (e.g. "12.5K", "1.2M").
    static func formatTokenCount(_ count: Int) -> String {
        switch count {
        case ..<1000:
            return "\(count)"
        case ..<1_000_000:
            let thousands = Double(count) / 1000.0
            return thousands.truncatingRemainder(dividingBy: 1.0) == 0
                ? "\(Int(thousands))K"
                : String(format: "%.1fK", thousands)
        default:
            let millions = Double(count) / 1_000_000.0
            return millions.truncatingRemainder(dividingBy: 1.0) == 0
                ? "\(Int(millions))M"
                : String(format: "%.1fM", millions)
        }
    }
}
