@testable import OICore
import Testing

// MARK: - MockRunningApp

/// Lightweight mock for `RunningAppInfo` used in detection logic tests.
struct MockRunningApp: RunningAppInfo, Sendable {
    let bundleIdentifier: String?
    let processIdentifier: Int32
    let isTerminated: Bool
}

// MARK: - SingleInstanceGuardTests

struct SingleInstanceGuardTests {
    // MARK: Internal

    @Test
    func `Returns nil when no other instances are running`() {
        let apps: [MockRunningApp] = [
            MockRunningApp(bundleIdentifier: "com.other.app", processIdentifier: 200, isTerminated: false),
            MockRunningApp(bundleIdentifier: "com.another.app", processIdentifier: 300, isTerminated: false),
        ]

        let result = SingleInstanceGuard.findExistingInstance(
            bundleID: Self.targetBundleID,
            currentPID: Self.currentPID,
            runningApps: apps,
        )

        #expect(result == nil)
    }

    @Test
    func `Finds existing instance with matching bundle ID`() {
        let apps: [MockRunningApp] = [
            MockRunningApp(bundleIdentifier: "com.other.app", processIdentifier: 200, isTerminated: false),
            MockRunningApp(bundleIdentifier: Self.targetBundleID, processIdentifier: 300, isTerminated: false),
        ]

        let result = SingleInstanceGuard.findExistingInstance(
            bundleID: Self.targetBundleID,
            currentPID: Self.currentPID,
            runningApps: apps,
        )

        #expect(result?.processIdentifier == 300)
    }

    @Test
    func `Excludes the current process from results`() {
        let apps: [MockRunningApp] = [
            MockRunningApp(bundleIdentifier: Self.targetBundleID, processIdentifier: Self.currentPID, isTerminated: false),
        ]

        let result = SingleInstanceGuard.findExistingInstance(
            bundleID: Self.targetBundleID,
            currentPID: Self.currentPID,
            runningApps: apps,
        )

        #expect(result == nil)
    }

    @Test
    func `Excludes terminated instances`() {
        let apps: [MockRunningApp] = [
            MockRunningApp(bundleIdentifier: Self.targetBundleID, processIdentifier: 200, isTerminated: true),
        ]

        let result = SingleInstanceGuard.findExistingInstance(
            bundleID: Self.targetBundleID,
            currentPID: Self.currentPID,
            runningApps: apps,
        )

        #expect(result == nil)
    }

    @Test
    func `Returns nil for empty app list`() {
        let apps: [MockRunningApp] = []

        let result = SingleInstanceGuard.findExistingInstance(
            bundleID: Self.targetBundleID,
            currentPID: Self.currentPID,
            runningApps: apps,
        )

        #expect(result == nil)
    }

    @Test
    func `Excludes apps with nil bundle identifier`() {
        let apps: [MockRunningApp] = [
            MockRunningApp(bundleIdentifier: nil, processIdentifier: 200, isTerminated: false),
        ]

        let result = SingleInstanceGuard.findExistingInstance(
            bundleID: Self.targetBundleID,
            currentPID: Self.currentPID,
            runningApps: apps,
        )

        #expect(result == nil)
    }

    @Test(
        arguments: [
            (bundleID: "com.example.open-island" as String?, pid: Int32(200), terminated: false, shouldMatch: true),
            (bundleID: "com.example.open-island" as String?, pid: Int32(100), terminated: false, shouldMatch: false),
            (bundleID: "com.example.open-island" as String?, pid: Int32(200), terminated: true, shouldMatch: false),
            (bundleID: "com.other.app" as String?, pid: Int32(200), terminated: false, shouldMatch: false),
            (bundleID: nil as String?, pid: Int32(200), terminated: false, shouldMatch: false),
        ],
    )
    func `Parameterized detection scenarios`(bundleID: String?, pid: Int32, terminated: Bool, shouldMatch: Bool) {
        let apps = [MockRunningApp(bundleIdentifier: bundleID, processIdentifier: pid, isTerminated: terminated)]

        let result = SingleInstanceGuard.findExistingInstance(
            bundleID: Self.targetBundleID,
            currentPID: Self.currentPID,
            runningApps: apps,
        )

        #expect((result != nil) == shouldMatch)
    }

    // MARK: Private

    private static let targetBundleID = "com.example.open-island"
    private static let currentPID: Int32 = 100
}
