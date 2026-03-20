package import SwiftUI

// MARK: - AppSettings

// UserDefaults is documented as thread-safe by Apple. Static computed
// properties here delegate directly to UserDefaults — no Mutex needed.
// Do NOT add Mutex wrapping or actor isolation to these accessors.

/// Central settings store backed by `UserDefaults`.
///
/// All properties are static computed — reads and writes go directly
/// through `UserDefaults.standard`. The struct carries no stored state.
package struct AppSettings: Sendable {
    // MARK: Lifecycle

    private init() {}

    // MARK: Package

    /// Brand teal accent color (`#14B8A6`), used as the default mascot color.
    package static let brandTeal = Color(hex: "#14B8A6")! // swiftlint:disable:this force_unwrapping

    /// The sound played for notifications.
    package static var notificationSound: NotificationSound {
        get {
            UserDefaults.standard.string(forKey: Key.notificationSound)
                .flatMap(NotificationSound.init(rawValue:)) ?? .default
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.notificationSound) }
    }

    /// When to suppress notification sounds.
    package static var soundSuppression: SoundSuppression {
        get {
            UserDefaults.standard.string(forKey: Key.soundSuppression)
                .flatMap(SoundSuppression.init(rawValue:)) ?? .whenFocused
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.soundSuppression) }
    }

    /// Accent color for the mascot, stored as a hex string (e.g., `"#FF6600"`).
    package static var mascotColor: Color {
        get {
            UserDefaults.standard.string(forKey: Key.mascotColor)
                .flatMap { Color(hex: $0) } ?? brandTeal
        }
        set { UserDefaults.standard.set(newValue.hexString, forKey: Key.mascotColor) }
    }

    /// Whether the mascot is always visible in the notch.
    package static var mascotAlwaysVisible: Bool {
        get {
            UserDefaults.standard.object(forKey: Key.mascotAlwaysVisible) == nil
                ? true
                : UserDefaults.standard.bool(forKey: Key.mascotAlwaysVisible)
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.mascotAlwaysVisible) }
    }

    /// Whether the notch auto-expands on events.
    package static var notchAutoExpand: Bool {
        get {
            UserDefaults.standard.object(forKey: Key.notchAutoExpand) == nil
                ? true
                : UserDefaults.standard.bool(forKey: Key.notchAutoExpand)
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.notchAutoExpand) }
    }

    /// The set of enabled provider IDs, stored as a JSON-encoded array of raw values.
    package static var enabledProviders: Set<ProviderID> {
        get {
            guard let data = UserDefaults.standard.data(forKey: Key.enabledProviders),
                  let rawValues = try? JSONDecoder().decode([String].self, from: data)
            else {
                return Set<ProviderID>()
            }
            return Set(rawValues.compactMap(ProviderID.init(rawValue:)))
        }
        set {
            let rawValues = newValue.map(\.rawValue)
            if let data = try? JSONEncoder().encode(rawValues) {
                UserDefaults.standard.set(data, forKey: Key.enabledProviders)
            }
        }
    }

    /// Enables verbose/debug logging.
    package static var verboseMode: Bool {
        get { UserDefaults.standard.bool(forKey: Key.verboseMode) }
        set { UserDefaults.standard.set(newValue, forKey: Key.verboseMode) }
    }

    // MARK: Private

    // MARK: - Keys

    private enum Key {
        static let notificationSound = "oi_notificationSound"
        static let soundSuppression = "oi_soundSuppression"
        static let mascotColor = "oi_mascotColor"
        static let mascotAlwaysVisible = "oi_mascotAlwaysVisible"
        static let notchAutoExpand = "oi_notchAutoExpand"
        static let enabledProviders = "oi_enabledProviders"
        static let verboseMode = "oi_verboseMode"
    }
}

// MARK: - ProviderID + allKnown

package extension ProviderID {
    /// All known provider IDs — used as the default for `enabledProviders`.
    static let allKnown: [ProviderID] = [.claude, .codex, .geminiCLI, .openCode]
}

// MARK: - Color + Hex Conversion

package extension Color {
    /// Creates a `Color` from a hex string (e.g., `"#D97706"` or `"D97706"`).
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }
        guard hexString.count == 6, let rgb = UInt64(hexString, radix: 16) else {
            return nil
        }
        let red = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8) & 0xFF) / 255.0
        let blue = Double(rgb & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue)
    }

    /// Returns the hex string representation (e.g., `"#FF6600"`).
    var hexString: String {
        let resolved = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let red = Int(round(resolved.redComponent * 255))
        let green = Int(round(resolved.greenComponent * 255))
        let blue = Int(round(resolved.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
