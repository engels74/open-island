/// The file format used for a provider's configuration files.
package enum ConfigFileFormat: Sendable, Hashable, BitwiseCopyable {
    case json
    case toml
}
