import Foundation
public import OICore

// MARK: - ProviderSetupCoordinator

/// Central orchestrator for provider setup and teardown.
///
/// Manages the full lifecycle: prerequisite checking, config backup creation,
/// hook installation, and verification. Each provider has its own setup
/// requirements based on its transport type.
///
/// - Claude Code & Gemini CLI: require Python runtime + hook installation into settings.json
/// - Codex CLI: only requires CLI binary on PATH (JSON-RPC, no hooks)
/// - OpenCode: only requires CLI binary on PATH (HTTP SSE, no hooks)
public actor ProviderSetupCoordinator {
    // MARK: Lifecycle

    public init() {
        self.backupManager = ConfigBackupManager()
    }

    /// Internal initializer allowing injection of a custom backup manager (for testing).
    package init(backupManager: ConfigBackupManager) {
        self.backupManager = backupManager
    }

    // MARK: Public

    /// Returns what setup will involve for the given provider.
    public func setupRequirements(for provider: ProviderID) -> ProviderSetupRequirements {
        let metadata = ProviderMetadata.metadata(for: provider)

        switch provider {
        case .claude:
            return ProviderSetupRequirements(
                prerequisites: Self.claudePrerequisites,
                steps: Self.hookSetupSteps(
                    provider: provider,
                    configDir: "~/.claude",
                    scriptName: ClaudeHookInstaller.hookScriptName,
                ),
                estimatedDuration: "~10 seconds",
            )

        case .geminiCLI:
            return ProviderSetupRequirements(
                prerequisites: Self.geminiPrerequisites,
                steps: Self.hookSetupSteps(
                    provider: provider,
                    configDir: "~/.gemini",
                    scriptName: GeminiHookInstaller.hookScriptName,
                ),
                estimatedDuration: "~10 seconds",
            )

        case .codex:
            return ProviderSetupRequirements(
                prerequisites: Self.binaryOnlyPrerequisites(metadata: metadata),
                steps: [],
                estimatedDuration: "~5 seconds",
            )

        case .openCode:
            return ProviderSetupRequirements(
                prerequisites: Self.binaryOnlyPrerequisites(metadata: metadata),
                steps: [],
                estimatedDuration: "~5 seconds",
            )

        case .example:
            return ProviderSetupRequirements(
                prerequisites: [],
                steps: [],
                estimatedDuration: nil,
            )
        }
    }

    /// Check whether all prerequisites are met for the given provider.
    public func checkPrerequisites(for provider: ProviderID) async -> [PrerequisiteCheckResult] {
        let requirements = self.setupRequirements(for: provider)
        var results: [PrerequisiteCheckResult] = []

        for prereq in requirements.prerequisites {
            let result = Self.evaluatePrerequisite(prereq, for: provider)
            results.append(result)
        }

        return results
    }

    /// Run the full setup flow for a provider.
    ///
    /// Steps: check prerequisites → backup config → install hooks → verify.
    public func install(
        provider: ProviderID,
        progressHandler: @Sendable (SetupProgress) -> Void,
    ) async throws(ProviderSetupError) {
        // 1. Check prerequisites
        progressHandler(.checkingPrerequisites)
        let prereqResults = await checkPrerequisites(for: provider)
        let failures = prereqResults.filter { !$0.passed }
        guard failures.isEmpty else {
            throw .prerequisitesNotMet(failures)
        }

        // 2. Back up existing config files before modification
        let configPaths = Self.configPaths(for: provider)
        for path in configPaths {
            let expandedPath = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                progressHandler(.creatingBackup(path: path))
                do {
                    _ = try self.backupManager.createBackup(for: expandedPath, provider: provider)
                } catch {
                    throw .backupFailed(error)
                }
            }
        }

        // 3. Install hooks (for providers that need them)
        progressHandler(.installingHooks)
        switch provider {
        case .claude:
            do {
                try await ClaudeHookInstaller.install()
            } catch {
                throw .hookInstallFailed(error)
            }

        case .geminiCLI:
            do {
                try await GeminiHookInstaller.install()
            } catch {
                throw .hookInstallFailed(error)
            }

        case .codex,
             .openCode,
             .example:
            break // No hook installation needed
        }

        // 4. Verify
        progressHandler(.verifying)
        let verification = await verify(provider: provider)
        guard verification.success else {
            throw .verificationFailed(verification.message)
        }

        progressHandler(.complete)
    }

    /// Reverse setup for a provider — remove hooks and clean up.
    public func uninstall(provider: ProviderID) async throws(ProviderSetupError) {
        switch provider {
        case .claude:
            do {
                try await ClaudeHookInstaller.uninstall()
            } catch {
                throw .hookInstallFailed(error)
            }

        case .geminiCLI:
            do {
                try await GeminiHookInstaller.uninstall()
            } catch {
                throw .hookInstallFailed(error)
            }

        case .codex,
             .openCode,
             .example:
            break // Nothing to uninstall
        }
    }

    /// Verify that a provider's setup is correct.
    public func verify(provider: ProviderID) async -> VerificationResult {
        let metadata = ProviderMetadata.metadata(for: provider)

        switch provider {
        case .claude:
            return Self.verifyHookProvider(
                metadata: metadata,
                isInstalled: ClaudeHookInstaller.isInstalled(),
                providerName: "Claude Code",
            )

        case .geminiCLI:
            return Self.verifyHookProvider(
                metadata: metadata,
                isInstalled: GeminiHookInstaller.isInstalled(),
                providerName: "Gemini CLI",
            )

        case .codex:
            return Self.verifyBinaryProvider(metadata: metadata, providerName: "Codex")

        case .openCode:
            return Self.verifyBinaryProvider(metadata: metadata, providerName: "OpenCode")

        case .example:
            return VerificationResult(success: true, message: "Example provider is always available.")
        }
    }

    // MARK: Private

    private let backupManager: ConfigBackupManager
}

// MARK: - Prerequisite Definitions & Evaluation

extension ProviderSetupCoordinator {
    private static let claudePrerequisites: [ProviderPrerequisite] = [
        ProviderPrerequisite(
            id: "claude-binary",
            description: "Claude Code CLI must be installed",
            checkDescription: "Claude CLI binary on PATH",
        ),
        ProviderPrerequisite(
            id: "claude-python",
            description: "Python 3.14+ or uv required for hook scripts",
            checkDescription: "Python runtime for hooks",
        ),
    ]

    private static let geminiPrerequisites: [ProviderPrerequisite] = [
        ProviderPrerequisite(
            id: "gemini-binary",
            description: "Gemini CLI must be installed",
            checkDescription: "Gemini CLI binary on PATH",
        ),
        ProviderPrerequisite(
            id: "gemini-python",
            description: "Python 3.14+ or uv required for hook scripts",
            checkDescription: "Python runtime for hooks",
        ),
    ]

    private static func binaryOnlyPrerequisites(
        metadata: ProviderMetadata,
    ) -> [ProviderPrerequisite] {
        [
            ProviderPrerequisite(
                id: "\(metadata.cliBinaryNames.first ?? "cli")-binary",
                description: "\(metadata.displayName) CLI must be installed",
                checkDescription: "\(metadata.displayName) binary on PATH",
            ),
        ]
    }

    private static func evaluatePrerequisite(
        _ prereq: ProviderPrerequisite,
        for provider: ProviderID,
    ) -> PrerequisiteCheckResult {
        switch prereq.id {
        case "claude-binary":
            self.checkBinaryOnPath(
                names: ProviderMetadata.metadata(for: .claude).cliBinaryNames,
                prerequisite: prereq,
            )

        case "gemini-binary":
            self.checkBinaryOnPath(
                names: ProviderMetadata.metadata(for: .geminiCLI).cliBinaryNames,
                prerequisite: prereq,
            )

        case "codex-binary":
            self.checkBinaryOnPath(
                names: ProviderMetadata.metadata(for: .codex).cliBinaryNames,
                prerequisite: prereq,
            )

        case "opencode-binary":
            self.checkBinaryOnPath(
                names: ProviderMetadata.metadata(for: .openCode).cliBinaryNames,
                prerequisite: prereq,
            )

        case "claude-python",
             "gemini-python":
            self.checkPythonRuntime(prerequisite: prereq)

        default:
            PrerequisiteCheckResult(
                prerequisite: prereq,
                passed: false,
                detail: "Unknown prerequisite: \(prereq.id)",
            )
        }
    }

    /// Check if any of the given binary names are available on PATH.
    private static func checkBinaryOnPath(
        names: [String],
        prerequisite: ProviderPrerequisite,
    ) -> PrerequisiteCheckResult {
        for name in names {
            if let path = resolveInPATH(name) {
                return PrerequisiteCheckResult(
                    prerequisite: prerequisite,
                    passed: true,
                    detail: "Found at \(path)",
                )
            }
        }

        return PrerequisiteCheckResult(
            prerequisite: prerequisite,
            passed: false,
            detail: "None of \(names.joined(separator: ", ")) found on PATH",
        )
    }

    /// Check if Python 3.14+ or uv is available.
    private static func checkPythonRuntime(
        prerequisite: ProviderPrerequisite,
    ) -> PrerequisiteCheckResult {
        do {
            let command = try HookRuntimeDetector.detect()
            let detail = switch command {
            case let .uv(path):
                "uv found at \(path)"
            case let .python(path):
                "Python found at \(path)"
            }
            return PrerequisiteCheckResult(
                prerequisite: prerequisite,
                passed: true,
                detail: detail,
            )
        } catch {
            return PrerequisiteCheckResult(
                prerequisite: prerequisite,
                passed: false,
                detail: error.description,
            )
        }
    }
}

// MARK: - Verification Helpers

extension ProviderSetupCoordinator {
    private static func verifyHookProvider(
        metadata: ProviderMetadata,
        isInstalled: Bool,
        providerName: String,
    ) -> VerificationResult {
        var details: [String] = []
        var allPassed = true

        // Check binary
        let hasBinary = metadata.cliBinaryNames.contains { self.resolveInPATH($0) != nil }
        details.append(hasBinary ? "CLI binary: found" : "CLI binary: not found")
        if !hasBinary { allPassed = false }

        // Check hooks installed
        details.append(isInstalled ? "Hooks: installed" : "Hooks: not installed")
        if !isInstalled { allPassed = false }

        let message = allPassed
            ? "\(providerName) is ready."
            : "\(providerName) setup is incomplete."

        return VerificationResult(success: allPassed, message: message, details: details)
    }

    private static func verifyBinaryProvider(
        metadata: ProviderMetadata,
        providerName: String,
    ) -> VerificationResult {
        let hasBinary = metadata.cliBinaryNames.contains { self.resolveInPATH($0) != nil }

        if hasBinary {
            return VerificationResult(
                success: true,
                message: "\(providerName) is ready.",
                details: ["CLI binary: found"],
            )
        } else {
            return VerificationResult(
                success: false,
                message: "\(providerName) CLI not found on PATH.",
                details: ["CLI binary: not found"],
            )
        }
    }
}

// MARK: - Setup Steps & PATH Resolution

extension ProviderSetupCoordinator {
    private static func hookSetupSteps(
        provider: ProviderID,
        configDir: String,
        scriptName: String,
    ) -> [ProviderSetupStep] {
        [
            ProviderSetupStep(
                id: "\(provider.rawValue)-copy-script",
                title: "Copy hook script",
                description: "Copies the Open Island hook script to \(configDir)/hooks/",
                isDestructive: false,
                affectedPaths: ["\(configDir)/hooks/\(scriptName)"],
            ),
            ProviderSetupStep(
                id: "\(provider.rawValue)-update-settings",
                title: "Register hooks in settings",
                description: "Adds Open Island hook entries to \(configDir)/settings.json",
                isDestructive: false,
                affectedPaths: ["\(configDir)/settings.json"],
            ),
        ]
    }

    private static func configPaths(for provider: ProviderID) -> [String] {
        switch provider {
        case .claude:
            ["~/.claude/settings.json"]
        case .geminiCLI:
            ["~/.gemini/settings.json"]
        case .codex,
             .openCode,
             .example:
            [] // No config files to back up
        }
    }

    /// Resolve a binary name to an absolute path using `which`.
    private static func resolveInPATH(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let path, !path.isEmpty else { return nil }
        return path
    }
}
