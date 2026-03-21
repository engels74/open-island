import Foundation
@testable import OICore
import Testing

// MARK: - ProviderInstallationStatusTests

struct ProviderInstallationStatusTests {
    @Test
    func `notInstalled case exists`() {
        let status: ProviderInstallationStatus = .notInstalled
        if case .notInstalled = status {
        } else {
            Issue.record("Expected .notInstalled")
        }
    }

    @Test
    func `installing case exists`() {
        let status: ProviderInstallationStatus = .installing
        if case .installing = status {
        } else {
            Issue.record("Expected .installing")
        }
    }

    @Test
    func `installed case exists`() {
        let status: ProviderInstallationStatus = .installed
        if case .installed = status {
            // pass
        } else {
            Issue.record("Expected .installed")
        }
    }

    @Test
    func `failed case carries error`() {
        struct TestError: Error, CustomStringConvertible {
            let description = "test failure"
        }

        let error = TestError()
        let status: ProviderInstallationStatus = .failed(error)
        if case let .failed(capturedError) = status {
            #expect(capturedError is TestError)
        } else {
            Issue.record("Expected .failed")
        }
    }

    @Test
    func `is Sendable`() {
        let status: ProviderInstallationStatus = .installed
        let sendable: any Sendable = status
        _ = sendable // Compilation is the test
    }
}

// MARK: - ProviderSetupStepTests

struct ProviderSetupStepTests {
    @Test
    func `initializes with all properties`() {
        let step = ProviderSetupStep(
            id: "test-step",
            title: "Test Step",
            description: "A step for testing",
            isDestructive: true,
            affectedPaths: ["~/.config/test.json", "~/.config/hooks/"],
        )

        #expect(step.id == "test-step")
        #expect(step.title == "Test Step")
        #expect(step.description == "A step for testing")
        #expect(step.isDestructive == true)
        #expect(step.affectedPaths.count == 2)
        #expect(step.affectedPaths[0] == "~/.config/test.json")
    }

    @Test
    func `non-destructive step`() {
        let step = ProviderSetupStep(
            id: "safe-step",
            title: "Safe",
            description: "Non-destructive",
            isDestructive: false,
            affectedPaths: [],
        )

        #expect(step.isDestructive == false)
        #expect(step.affectedPaths.isEmpty)
    }

    @Test
    func `is Sendable`() {
        let step = ProviderSetupStep(
            id: "s", title: "t", description: "d",
            isDestructive: false, affectedPaths: [],
        )
        let sendable: any Sendable = step
        _ = sendable
    }
}

// MARK: - ProviderPrerequisiteTests

struct ProviderPrerequisiteTests {
    @Test
    func `initializes with all properties`() {
        let prereq = ProviderPrerequisite(
            id: "python-check",
            description: "Python 3.14+ required",
            checkDescription: "Python runtime for hooks",
        )

        #expect(prereq.id == "python-check")
        #expect(prereq.description == "Python 3.14+ required")
        #expect(prereq.checkDescription == "Python runtime for hooks")
    }

    @Test
    func `is Sendable`() {
        let prereq = ProviderPrerequisite(
            id: "p", description: "d", checkDescription: "c",
        )
        let sendable: any Sendable = prereq
        _ = sendable
    }
}

// MARK: - ProviderSetupRequirementsTests

struct ProviderSetupRequirementsTests {
    @Test
    func `initializes with prerequisites and steps`() {
        let prereq = ProviderPrerequisite(
            id: "binary",
            description: "CLI must be installed",
            checkDescription: "Binary on PATH",
        )
        let step = ProviderSetupStep(
            id: "install-hook",
            title: "Install hook",
            description: "Copies hook script",
            isDestructive: false,
            affectedPaths: ["~/.config/hooks/"],
        )

        let requirements = ProviderSetupRequirements(
            prerequisites: [prereq],
            steps: [step],
            estimatedDuration: "~10 seconds",
        )

        #expect(requirements.prerequisites.count == 1)
        #expect(requirements.prerequisites[0].id == "binary")
        #expect(requirements.steps.count == 1)
        #expect(requirements.steps[0].id == "install-hook")
        #expect(requirements.estimatedDuration == "~10 seconds")
    }

    @Test
    func `nil estimated duration`() {
        let requirements = ProviderSetupRequirements(
            prerequisites: [],
            steps: [],
            estimatedDuration: nil,
        )

        #expect(requirements.prerequisites.isEmpty)
        #expect(requirements.steps.isEmpty)
        #expect(requirements.estimatedDuration == nil)
    }

    @Test
    func `is Sendable`() {
        let requirements = ProviderSetupRequirements(
            prerequisites: [], steps: [], estimatedDuration: nil,
        )
        let sendable: any Sendable = requirements
        _ = sendable
    }
}

// MARK: - AppSettingsEnabledProvidersTests

@Suite(.serialized)
struct AppSettingsEnabledProvidersTests {
    @Test
    func `defaults to empty set on fresh UserDefaults`() {
        // Remove the key to simulate fresh install
        UserDefaults.standard.removeObject(forKey: "oi_enabledProviders")
        let providers = AppSettings.enabledProviders
        #expect(providers.isEmpty)
    }

    @Test
    func `round-trips provider set through UserDefaults`() {
        let original: Set<ProviderID> = [.claude, .codex]
        AppSettings.enabledProviders = original
        let loaded = AppSettings.enabledProviders
        #expect(loaded == original)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "oi_enabledProviders")
    }

    @Test
    func `empty set persists correctly`() {
        AppSettings.enabledProviders = []
        let loaded = AppSettings.enabledProviders
        #expect(loaded.isEmpty)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "oi_enabledProviders")
    }

    @Test
    func `allKnown contains expected providers`() {
        let allKnown = ProviderID.allKnown
        #expect(allKnown.contains(.claude))
        #expect(allKnown.contains(.codex))
        #expect(allKnown.contains(.geminiCLI))
        #expect(allKnown.contains(.openCode))
        #expect(allKnown.count == 4)
    }
}
