/// The file format used for a provider's configuration files.
public enum ConfigFileFormat: Sendable, Hashable, BitwiseCopyable {
    case json
    case toml
}
