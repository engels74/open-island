// swift-tools-version: 6.2

import PackageDescription

let upcomingFeatures: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

/// Test targets exclude NonisolatedNonsendingByDefault because it is ABI-incompatible
/// with Swift Testing's TestScoping protocol.
let testSettings: [SwiftSetting] = [
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "OpenIslandKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OICore", targets: ["OICore"]),
        .library(name: "OIProviders", targets: ["OIProviders"]),
        .library(name: "OIWindow", targets: ["OIWindow"]),
        .library(name: "OIModules", targets: ["OIModules"]),
        .library(name: "OIState", targets: ["OIState"]),
        .library(name: "OIUI", targets: ["OIUI"]),
    ],
    targets: [
        .target(
            name: "OICore",
            swiftSettings: upcomingFeatures,
        ),
        .target(
            name: "OIProviders",
            dependencies: ["OICore"],
            resources: [
                .copy("Resources/Hooks"),
            ],
            swiftSettings: upcomingFeatures,
        ),
        .target(
            name: "OIWindow",
            dependencies: ["OICore"],
            swiftSettings: upcomingFeatures,
        ),
        .target(
            name: "OIModules",
            dependencies: ["OICore"],
            swiftSettings: upcomingFeatures,
        ),
        .target(
            name: "OIState",
            dependencies: ["OICore", "OIProviders"],
            swiftSettings: upcomingFeatures,
        ),
        .target(
            name: "OIUI",
            dependencies: ["OICore", "OIState", "OIModules", "OIWindow"],
            swiftSettings: upcomingFeatures,
        ),
        .testTarget(
            name: "OICoreTests",
            dependencies: ["OICore"],
            swiftSettings: testSettings,
        ),
        .testTarget(
            name: "OIStateTests",
            dependencies: ["OIState", "OICore", "OIProviders"],
            swiftSettings: testSettings,
        ),
        .testTarget(
            name: "OIProvidersTests",
            dependencies: ["OIProviders", "OICore"],
            swiftSettings: testSettings,
        ),
        .testTarget(
            name: "OIWindowTests",
            dependencies: ["OIWindow", "OICore"],
            swiftSettings: testSettings,
        ),
        .testTarget(
            name: "OIModulesTests",
            dependencies: ["OIModules", "OICore"],
            swiftSettings: testSettings,
        ),
    ],
)
