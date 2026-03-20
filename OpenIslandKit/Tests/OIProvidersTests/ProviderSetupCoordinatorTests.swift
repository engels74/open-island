import Foundation
@testable import OICore
@testable import OIProviders
import Testing

// MARK: - ProviderSetupCoordinatorTests

struct ProviderSetupCoordinatorTests {
    // MARK: - setupRequirements tests

    @Test
    func `Claude requires two prerequisites — binary and python`() async {
        let coordinator = ProviderSetupCoordinator()
        let requirements = await coordinator.setupRequirements(for: .claude)

        #expect(requirements.prerequisites.count == 2)
        let ids = requirements.prerequisites.map(\.id)
        #expect(ids.contains("claude-binary"))
        #expect(ids.contains("claude-python"))
    }

    @Test
    func `Claude has hook setup steps`() async {
        let coordinator = ProviderSetupCoordinator()
        let requirements = await coordinator.setupRequirements(for: .claude)

        #expect(requirements.steps.count == 2)
        let stepIDs = requirements.steps.map(\.id)
        #expect(stepIDs.contains("claude-copy-script"))
        #expect(stepIDs.contains("claude-update-settings"))
        #expect(requirements.estimatedDuration == "~10 seconds")
    }

    @Test
    func `Claude steps reference correct config directory`() async {
        let coordinator = ProviderSetupCoordinator()
        let requirements = await coordinator.setupRequirements(for: .claude)

        let affectedPaths = requirements.steps.flatMap(\.affectedPaths)
        #expect(affectedPaths.allSatisfy { $0.contains(".claude") })
    }

    @Test
    func `Gemini requires two prerequisites — binary and python`() async {
        let coordinator = ProviderSetupCoordinator()
        let requirements = await coordinator.setupRequirements(for: .geminiCLI)

        #expect(requirements.prerequisites.count == 2)
        let ids = requirements.prerequisites.map(\.id)
        #expect(ids.contains("gemini-binary"))
        #expect(ids.contains("gemini-python"))
    }

    @Test
    func `Gemini has hook setup steps referencing gemini config`() async {
        let coordinator = ProviderSetupCoordinator()
        let requirements = await coordinator.setupRequirements(for: .geminiCLI)

        #expect(requirements.steps.count == 2)
        let affectedPaths = requirements.steps.flatMap(\.affectedPaths)
        #expect(affectedPaths.allSatisfy { $0.contains(".gemini") })
        #expect(requirements.estimatedDuration == "~10 seconds")
    }

    @Test
    func `Codex requires only binary prerequisite and no steps`() async {
        let coordinator = ProviderSetupCoordinator()
        let requirements = await coordinator.setupRequirements(for: .codex)

        #expect(requirements.prerequisites.count == 1)
        #expect(requirements.prerequisites[0].id == "codex-binary")
        #expect(requirements.steps.isEmpty)
        #expect(requirements.estimatedDuration == "~5 seconds")
    }

    @Test
    func `OpenCode requires only binary prerequisite and no steps`() async {
        let coordinator = ProviderSetupCoordinator()
        let requirements = await coordinator.setupRequirements(for: .openCode)

        #expect(requirements.prerequisites.count == 1)
        #expect(requirements.prerequisites[0].id == "openCode-binary")
        #expect(requirements.steps.isEmpty)
        #expect(requirements.estimatedDuration == "~5 seconds")
    }

    @Test
    func `Example provider has no prerequisites and no steps`() async {
        let coordinator = ProviderSetupCoordinator()
        let requirements = await coordinator.setupRequirements(for: .example)

        #expect(requirements.prerequisites.isEmpty)
        #expect(requirements.steps.isEmpty)
        #expect(requirements.estimatedDuration == nil)
    }

    @Test(arguments: [ProviderID.claude, .codex, .geminiCLI, .openCode, .example])
    func `all providers return non-nil requirements`(provider: ProviderID) async {
        let coordinator = ProviderSetupCoordinator()
        let requirements = await coordinator.setupRequirements(for: provider)
        // Just verify we get a valid ProviderSetupRequirements for every provider
        _ = requirements.prerequisites
        _ = requirements.steps
    }

    // MARK: - checkPrerequisites tests

    @Test
    func `checkPrerequisites returns results for each prerequisite`() async {
        let coordinator = ProviderSetupCoordinator()
        let results = await coordinator.checkPrerequisites(for: .claude)

        // Claude has 2 prerequisites, so we should get 2 results
        #expect(results.count == 2)
        let prereqIDs = results.map(\.prerequisite.id)
        #expect(prereqIDs.contains("claude-binary"))
        #expect(prereqIDs.contains("claude-python"))
    }

    @Test
    func `checkPrerequisites for example returns empty`() async {
        let coordinator = ProviderSetupCoordinator()
        let results = await coordinator.checkPrerequisites(for: .example)
        #expect(results.isEmpty)
    }

    @Test
    func `prerequisite results have detail messages`() async throws {
        let coordinator = ProviderSetupCoordinator()
        let results = await coordinator.checkPrerequisites(for: .codex)

        #expect(results.count == 1)
        // Whether it passes or fails, there should be a detail string
        #expect(results[0].detail != nil)
        #expect(try !#require(results[0].detail?.isEmpty))
    }

    // MARK: - verify tests

    @Test
    func `verify example provider always succeeds`() async {
        let coordinator = ProviderSetupCoordinator()
        let result = await coordinator.verify(provider: .example)

        #expect(result.success == true)
        #expect(result.message.contains("Example"))
    }

    @Test(arguments: [ProviderID.claude, .codex, .geminiCLI, .openCode])
    func `verify returns non-empty message for all providers`(provider: ProviderID) async {
        let coordinator = ProviderSetupCoordinator()
        let result = await coordinator.verify(provider: provider)
        #expect(!result.message.isEmpty)
    }

    // MARK: - ConfigBackupManager integration

    @Test
    func `coordinator uses injected backup manager`() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OICoordinatorTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let backupsDir = tempDir.appendingPathComponent("backups", isDirectory: true)
        let manager = ConfigBackupManager(backupsBaseURL: backupsDir)
        let coordinator = ProviderSetupCoordinator(backupManager: manager)

        // Verify the coordinator was created with the custom backup manager
        // We test this indirectly — the coordinator should work without error
        let requirements = await coordinator.setupRequirements(for: .codex)
        #expect(requirements.prerequisites.count == 1)
    }

    // MARK: - Hook setup steps structure tests

    @Test
    func `hook providers have copy-script and update-settings steps`() async {
        let coordinator = ProviderSetupCoordinator()

        for provider in [ProviderID.claude, .geminiCLI] {
            let requirements = await coordinator.setupRequirements(for: provider)
            let stepIDs = requirements.steps.map(\.id)

            #expect(
                stepIDs.contains { $0.hasSuffix("-copy-script") },
                "Expected copy-script step for \(provider)",
            )
            #expect(
                stepIDs.contains { $0.hasSuffix("-update-settings") },
                "Expected update-settings step for \(provider)",
            )
        }
    }

    @Test
    func `binary-only providers have no setup steps`() async {
        let coordinator = ProviderSetupCoordinator()

        for provider in [ProviderID.codex, .openCode] {
            let requirements = await coordinator.setupRequirements(for: provider)
            #expect(requirements.steps.isEmpty, "Expected no steps for \(provider)")
        }
    }

    @Test
    func `setup steps are not destructive`() async {
        let coordinator = ProviderSetupCoordinator()

        for provider in [ProviderID.claude, .geminiCLI] {
            let requirements = await coordinator.setupRequirements(for: provider)
            for step in requirements.steps {
                #expect(step.isDestructive == false, "Step \(step.id) should not be destructive")
            }
        }
    }

    @Test
    func `prerequisite descriptions are human-readable`() async {
        let coordinator = ProviderSetupCoordinator()
        let requirements = await coordinator.setupRequirements(for: .claude)

        for prereq in requirements.prerequisites {
            #expect(!prereq.description.isEmpty)
            #expect(!prereq.checkDescription.isEmpty)
            #expect(!prereq.id.isEmpty)
        }
    }
}

// MARK: - SetupProgressTests

struct SetupProgressTests {
    @Test
    func `all progress cases exist`() {
        let cases: [SetupProgress] = [
            .checkingPrerequisites,
            .creatingBackup(path: "/test"),
            .installingHooks,
            .verifying,
            .complete,
        ]

        #expect(cases.count == 5)
    }

    @Test
    func `failed case carries error`() {
        struct TestError: Error {}
        let progress: SetupProgress = .failed(TestError())
        if case .failed = progress {
            // pass
        } else {
            Issue.record("Expected .failed")
        }
    }

    @Test
    func `is Sendable`() {
        let progress: SetupProgress = .complete
        let sendable: any Sendable = progress
        _ = sendable
    }
}

// MARK: - PrerequisiteCheckResultTests

struct PrerequisiteCheckResultTests {
    @Test
    func `initializes with all properties`() {
        let prereq = ProviderPrerequisite(
            id: "test", description: "desc", checkDescription: "check",
        )
        let result = PrerequisiteCheckResult(
            prerequisite: prereq,
            passed: true,
            detail: "Found at /usr/bin/test",
        )

        #expect(result.prerequisite.id == "test")
        #expect(result.passed == true)
        #expect(result.detail == "Found at /usr/bin/test")
    }

    @Test
    func `nil detail is valid`() {
        let prereq = ProviderPrerequisite(
            id: "test", description: "desc", checkDescription: "check",
        )
        let result = PrerequisiteCheckResult(prerequisite: prereq, passed: false)
        #expect(result.detail == nil)
    }
}

// MARK: - VerificationResultTests

struct VerificationResultTests {
    @Test
    func `initializes with success and message`() {
        let result = VerificationResult(
            success: true,
            message: "Provider is ready.",
        )

        #expect(result.success == true)
        #expect(result.message == "Provider is ready.")
        #expect(result.details == nil)
    }

    @Test
    func `initializes with details`() {
        let result = VerificationResult(
            success: false,
            message: "Setup incomplete.",
            details: ["CLI binary: not found", "Hooks: not installed"],
        )

        #expect(result.success == false)
        #expect(result.details?.count == 2)
    }
}

// MARK: - ProviderSetupErrorTests

struct ProviderSetupErrorTests {
    @Test
    func `prerequisitesNotMet carries failed results`() {
        let prereq = ProviderPrerequisite(
            id: "test", description: "desc", checkDescription: "check",
        )
        let failedResult = PrerequisiteCheckResult(
            prerequisite: prereq, passed: false, detail: "Not found",
        )

        let error: ProviderSetupError = .prerequisitesNotMet([failedResult])
        if case let .prerequisitesNotMet(results) = error {
            #expect(results.count == 1)
            #expect(results[0].passed == false)
        } else {
            Issue.record("Expected .prerequisitesNotMet")
        }
    }

    @Test
    func `verificationFailed carries message`() {
        let error: ProviderSetupError = .verificationFailed("Binary not found")
        if case let .verificationFailed(message) = error {
            #expect(message == "Binary not found")
        } else {
            Issue.record("Expected .verificationFailed")
        }
    }

    @Test
    func `unsupportedProvider carries provider ID`() {
        let error: ProviderSetupError = .unsupportedProvider(.example)
        if case let .unsupportedProvider(provider) = error {
            #expect(provider == .example)
        } else {
            Issue.record("Expected .unsupportedProvider")
        }
    }
}
