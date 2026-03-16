/// Controls when notification sounds are suppressed.
package enum SoundSuppression: String, Sendable, Hashable, Codable, CaseIterable {
    /// Always play sounds.
    case never
    /// Suppress when the app or terminal is focused.
    case whenFocused
    /// Suppress when the terminal window is visible.
    case whenVisible
}
