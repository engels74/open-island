// @preconcurrency: NSSound predates Sendable annotations
@preconcurrency import AppKit
public import Foundation

// MARK: - SoundManager

/// Plays notification sounds when sessions need user attention.
///
/// Rate-limits globally (one sound per ``globalCooldown``) and per-session
/// (one sound per ``sessionCooldown``) to prevent auditory spam.
/// Suppression modes allow silencing sounds based on app focus or
/// terminal visibility state.
@MainActor
public final class SoundManager {
    // MARK: Lifecycle

    public init(
        globalCooldown: TimeInterval = 5,
        sessionCooldown: TimeInterval = 15,
    ) {
        self.globalCooldown = globalCooldown
        self.sessionCooldown = sessionCooldown
    }

    // MARK: Public

    /// Plays the notification sound for a session if all suppression and
    /// rate-limiting checks pass.
    ///
    /// - Parameters:
    ///   - sessionID: Unique identifier for the session requesting attention.
    ///   - sound: Which sound to play.
    ///   - suppression: Current suppression policy.
    public func playIfAllowed(
        for sessionID: String,
        sound: NotificationSound,
        suppression: SoundSuppression,
    ) {
        guard sound != .none else { return }
        guard !self.isSuppressed(suppression) else { return }

        let now = ContinuousClock.now

        if let lastGlobal = lastPlayedAt,
           now - lastGlobal < .seconds(globalCooldown) {
            return
        }

        if let lastSession = sessionLastPlayed[sessionID],
           now - lastSession < .seconds(sessionCooldown) {
            return
        }

        self.play(sound)

        self.lastPlayedAt = now
        self.sessionLastPlayed[sessionID] = now
        self.pruneStaleEntries(before: now)
    }

    /// Removes tracking state for a session that has ended.
    public func clearSession(_ sessionID: String) {
        self.sessionLastPlayed.removeValue(forKey: sessionID)
    }

    // MARK: Private

    private let globalCooldown: TimeInterval
    private let sessionCooldown: TimeInterval

    private var lastPlayedAt: ContinuousClock.Instant?
    private var sessionLastPlayed: [String: ContinuousClock.Instant] = [:]

    /// Whether any known terminal window is visible on the current space.
    private var isTerminalVisible: Bool {
        TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace()
    }

    /// Whether a terminal application is currently the frontmost app.
    private var isTerminalFocused: Bool {
        TerminalVisibilityDetector.isTerminalFrontmost()
    }

    private func isSuppressed(_ suppression: SoundSuppression) -> Bool {
        switch suppression {
        case .never:
            false
        case .whenFocused:
            NSApp.isActive || self.isTerminalFocused
        case .whenVisible:
            self.isTerminalVisible
        }
    }

    private func play(_ sound: NotificationSound) {
        let nsSound: NSSound? = switch sound {
        case .default:
            NSSound(named: .init("Blow"))
        case .subtle:
            NSSound(named: .init("Tink"))
        case .chime:
            NSSound(named: .init("Glass"))
        case .none:
            nil
        }
        nsSound?.play()
    }

    /// Removes session entries older than twice the session cooldown
    /// to prevent unbounded growth.
    private func pruneStaleEntries(before now: ContinuousClock.Instant) {
        let threshold: Duration = .seconds(sessionCooldown * 2)
        self.sessionLastPlayed = self.sessionLastPlayed.filter { _, instant in
            now - instant < threshold
        }
    }
}
