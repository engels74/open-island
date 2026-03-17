package import Foundation

// MARK: - QuotaSnapshot

/// A point-in-time snapshot of provider quota/usage information.
package struct QuotaSnapshot: Sendable, Equatable {
    // MARK: Lifecycle

    package init(
        dailyLimit: Int? = nil,
        dailyUsed: Int? = nil,
        weeklyLimit: Int? = nil,
        weeklyUsed: Int? = nil,
        resetTime: Date? = nil,
        timestamp: Date,
    ) {
        self.dailyLimit = dailyLimit
        self.dailyUsed = dailyUsed
        self.weeklyLimit = weeklyLimit
        self.weeklyUsed = weeklyUsed
        self.resetTime = resetTime
        self.timestamp = timestamp
    }

    // MARK: Package

    /// Daily token limit, if the provider exposes one.
    package let dailyLimit: Int?

    /// Daily tokens consumed so far.
    package let dailyUsed: Int?

    /// Weekly token limit, if the provider exposes one.
    package let weeklyLimit: Int?

    /// Weekly tokens consumed so far.
    package let weeklyUsed: Int?

    /// When the current usage period resets.
    package let resetTime: Date?

    /// When this snapshot was captured.
    package let timestamp: Date

    /// Quota utilisation as a fraction (0.0–1.0), based on the most specific
    /// limit available (daily preferred over weekly). Returns `nil` when no
    /// limit information is available.
    package var utilizationFraction: Double? {
        if let limit = dailyLimit, limit > 0, let used = dailyUsed {
            return min(Double(used) / Double(limit), 1.0)
        }
        if let limit = weeklyLimit, limit > 0, let used = weeklyUsed {
            return min(Double(used) / Double(limit), 1.0)
        }
        return nil
    }
}

// MARK: - QuotaService

/// A provider-specific adapter that fetches quota/usage information.
///
/// Provider conformances can be stubs initially — Claude doesn't expose quota
/// via hooks, while Codex/Gemini/OpenCode have varying support levels.
package protocol QuotaService: Sendable {
    /// Fetch the current quota/usage for the provider.
    func fetchCurrentUsage() async throws -> QuotaSnapshot
}
