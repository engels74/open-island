package import Foundation

// MARK: - Per-Provider Settings

package extension AppSettings {
    /// Settings specific to the Claude Code provider.
    enum Claude {
        // MARK: Package

        /// Path to the Claude Code hook binary.
        package static var hookPath: String? {
            get { UserDefaults.standard.string(forKey: Key.hookPath) }
            set { UserDefaults.standard.set(newValue, forKey: Key.hookPath) }
        }

        // MARK: Private

        private enum Key {
            static let hookPath = "oi_claude_hookPath"
        }
    }

    /// Settings specific to the Codex provider.
    enum Codex {
        // MARK: Package

        /// Path to the Codex app-server binary.
        package static var appServerBinary: String? {
            get { UserDefaults.standard.string(forKey: Key.appServerBinary) }
            set { UserDefaults.standard.set(newValue, forKey: Key.appServerBinary) }
        }

        /// Approval policy override (e.g., "auto-edit", "suggest", "full-auto").
        package static var approvalPolicy: String? {
            get { UserDefaults.standard.string(forKey: Key.approvalPolicy) }
            set { UserDefaults.standard.set(newValue, forKey: Key.approvalPolicy) }
        }

        // MARK: Private

        private enum Key {
            static let appServerBinary = "oi_codex_appServerBinary"
            static let approvalPolicy = "oi_codex_approvalPolicy"
        }
    }

    /// Settings specific to the Gemini CLI provider.
    enum GeminiCLI {
        // MARK: Package

        /// Path to the Gemini CLI hook binary.
        package static var hookPath: String? {
            get { UserDefaults.standard.string(forKey: Key.hookPath) }
            set { UserDefaults.standard.set(newValue, forKey: Key.hookPath) }
        }

        /// Throttle interval in milliseconds after model response.
        package static var throttleAfterModelMs: Int? {
            get {
                UserDefaults.standard.object(forKey: Key.throttleAfterModelMs) == nil
                    ? nil
                    : UserDefaults.standard.integer(forKey: Key.throttleAfterModelMs)
            }
            set {
                if let newValue {
                    UserDefaults.standard.set(newValue, forKey: Key.throttleAfterModelMs)
                } else {
                    UserDefaults.standard.removeObject(forKey: Key.throttleAfterModelMs)
                }
            }
        }

        // MARK: Private

        private enum Key {
            static let hookPath = "oi_geminiCLI_hookPath"
            static let throttleAfterModelMs = "oi_geminiCLI_throttleAfterModelMs"
        }
    }

    /// Settings specific to the OpenCode provider.
    enum OpenCode {
        // MARK: Package

        /// Custom server port for the OpenCode SSE connection.
        package static var serverPort: Int? {
            get {
                UserDefaults.standard.object(forKey: Key.serverPort) == nil
                    ? nil
                    : UserDefaults.standard.integer(forKey: Key.serverPort)
            }
            set {
                if let newValue {
                    UserDefaults.standard.set(newValue, forKey: Key.serverPort)
                } else {
                    UserDefaults.standard.removeObject(forKey: Key.serverPort)
                }
            }
        }

        /// Whether to use mDNS for OpenCode discovery.
        package static var useMDNS: Bool {
            get { UserDefaults.standard.bool(forKey: Key.useMDNS) }
            set { UserDefaults.standard.set(newValue, forKey: Key.useMDNS) }
        }

        // MARK: Private

        private enum Key {
            static let serverPort = "oi_openCode_serverPort"
            static let useMDNS = "oi_openCode_useMDNS"
        }
    }
}
