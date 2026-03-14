/// Static metadata describing a provider's display properties and CLI configuration.
package struct ProviderMetadata: Sendable, Equatable {
    package let displayName: String
    package let iconName: String
    package let accentColorHex: String
    package let cliBinaryNames: [String]
    package let transportType: ProviderTransportType
    package let configFileFormat: ConfigFileFormat
    package let sessionLogDirectoryPath: String

    package static func metadata(for providerID: ProviderID) -> Self {
        switch providerID {
        case .claude:
            Self(
                displayName: "Claude Code",
                iconName: "brain.head.profile",
                accentColorHex: "#D97706",
                cliBinaryNames: ["claude"],
                transportType: .hookSocket,
                configFileFormat: .json,
                sessionLogDirectoryPath: "~/.claude/projects",
            )
        case .codex:
            Self(
                displayName: "Codex",
                iconName: "diamond",
                accentColorHex: "#10B981",
                cliBinaryNames: ["codex"],
                transportType: .jsonRPC,
                configFileFormat: .toml,
                sessionLogDirectoryPath: "~/.codex/sessions",
            )
        case .geminiCLI:
            Self(
                displayName: "Gemini CLI",
                iconName: "sparkles",
                accentColorHex: "#4285F4",
                cliBinaryNames: ["gemini"],
                transportType: .hookSocket,
                configFileFormat: .json,
                sessionLogDirectoryPath: "~/.gemini/sessions",
            )
        case .openCode:
            Self(
                displayName: "OpenCode",
                iconName: "chevron.left.forwardslash.chevron.right",
                accentColorHex: "#8B5CF6",
                cliBinaryNames: ["opencode"],
                transportType: .httpSSE,
                configFileFormat: .json,
                sessionLogDirectoryPath: "~/.opencode/sessions",
            )
        }
    }
}
