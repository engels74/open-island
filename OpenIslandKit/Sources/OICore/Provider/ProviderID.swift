/// Identifies a supported AI coding assistant provider.
public enum ProviderID: String, Sendable, Hashable, Codable {
    case claude
    case codex
    case geminiCLI
    case openCode
    case example
}
