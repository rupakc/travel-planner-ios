// swift-tools-version: 6.0
// Voyager iOS: every module, test target and dependency edge lives here (Task 1).
// A new edge is a manifest change that goes through the controller as its own small PR.
// `.macOS(.v14)` exists only so Foundation-level targets can be built and tested locally
// with `swift test` (no Xcode). CI on the iOS simulator is the authority.
import PackageDescription

/// Local mode for the Command Line Tools (no Xcode): `VOYAGERKIT_LOCAL=1 swift test --filter <T>Tests`.
/// The CLT have neither actool/xcstringstool (asset and String Catalogs) nor XCTest (which
/// SnapshotTesting needs), so local mode drops those resources, TestSupport and the view-level
/// test targets. Never set it on CI: CI builds the full graph.
let localCLT = Context.environment["VOYAGERKIT_LOCAL"] == "1"

func xcodeResources(_ path: String) -> (resources: [Resource]?, exclude: [String]) {
    localCLT ? (nil, [path]) : ([.process(path)], [])
}

let l10nResources = xcodeResources("Resources")
let designResources = xcodeResources("Resources")

// MARK: - Module names

let coreModules: [Target.Dependency] = [
    "VoyagerModel", "Networking", "AuthCore", "L10n", "DesignSystem", "Telemetry", "Domain",
]

let featureNames = [
    "FeatureAuth", "FeatureOnboarding", "FeatureTrips", "FeatureSearch", "FeatureDiscover",
    "FeatureCompare", "FeatureImport", "FeatureResults", "FeaturePlan", "FeatureShare",
    "FeatureChat", "FeatureAlerts", "FeatureNearby", "FeatureSettings", "FeaturePreferences",
    "FeatureAdmin", "FeatureAccount",
]

/// Features that render result sections (and so depend on SectionsUI).
let sectionFeatures: Set<String> = [
    "FeatureResults", "FeatureChat", "FeaturePlan", "FeatureShare", "FeatureTrips",
]

let snapshotTesting: Target.Dependency = .product(name: "SnapshotTesting", package: "swift-snapshot-testing")

// MARK: - Library targets

var targets: [Target] = [
    .target(name: "VoyagerModel"),
    .target(name: "Networking", dependencies: ["VoyagerModel"]),
    .target(name: "AuthCore", dependencies: ["VoyagerModel"]),
    .target(
        name: "L10n",
        dependencies: ["VoyagerModel"],
        exclude: l10nResources.exclude,
        resources: l10nResources.resources
    ),
    .target(name: "DesignSystem", exclude: designResources.exclude, resources: designResources.resources),
    .target(name: "Telemetry", dependencies: ["VoyagerModel"]),
    .target(name: "Domain", dependencies: ["VoyagerModel"]),
    .target(name: "VoyagerData", dependencies: ["VoyagerModel", "Networking", "AuthCore"]),
    .target(
        name: "SharedUI",
        dependencies: ["DesignSystem", "L10n", "Telemetry", "VoyagerModel", "Domain"]
    ),
    .target(name: "VoyagerEnv", dependencies: coreModules + ["VoyagerData", "SharedUI"]),
    .target(
        name: "SectionsUI",
        dependencies: ["SharedUI", "Domain", "VoyagerModel", "DesignSystem", "L10n", "Telemetry"]
    ),
    .target(name: "NotificationsCore", dependencies: ["VoyagerEnv", "VoyagerModel"]),
]

for name in featureNames {
    var deps: [Target.Dependency] = ["VoyagerEnv", "SharedUI"] + coreModules
    if sectionFeatures.contains(name) { deps.append("SectionsUI") }
    targets.append(.target(name: name, dependencies: deps))
}

targets += [
    .target(
        name: "AppShell",
        dependencies: featureNames.map { Target.Dependency(stringLiteral: $0) }
            + ["NotificationsCore", "VoyagerEnv", "SharedUI"] + coreModules
    ),
    // Test-only libraries: never reachable from the AppShell product.
    .target(name: "TestFixtures"),
]

if !localCLT {
    targets.append(
        .target(
            name: "TestSupport",
            dependencies: ["VoyagerEnv", "TestFixtures", snapshotTesting, "VoyagerData", "SharedUI"] + coreModules
        )
    )
}

// MARK: - Test targets

/// Test targets that render views: they also get TestSupport and SnapshotTesting,
/// and keep recorded PNGs in `__Snapshots__/` (excluded from the target's sources).
let uiTested = ["SharedUI", "SectionsUI", "VoyagerEnv", "AppShell"] + featureNames

let unitTested = [
    "VoyagerModel", "Networking", "AuthCore", "L10n", "DesignSystem", "Telemetry", "Domain",
    "VoyagerData", "NotificationsCore",
]

for name in unitTested {
    targets.append(
        .testTarget(
            name: "\(name)Tests",
            dependencies: [.target(name: name), "TestFixtures"],
            resources: name == "Telemetry" ? [.copy("Resources/telemetry_registry.json")] : nil
        )
    )
}

for name in uiTested where !localCLT {
    targets.append(
        .testTarget(
            name: "\(name)Tests",
            dependencies: [.target(name: name), "TestFixtures", "TestSupport", snapshotTesting],
            exclude: ["__Snapshots__"]
        )
    )
}

let package = Package(
    name: "VoyagerKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // The app links only AppShell (project.yml). VoyagerModel is a second product so Xcode
        // also generates the aggregate `VoyagerKit-Package` scheme that CI tests with.
        .library(name: "AppShell", targets: ["AppShell"]),
        .library(name: "VoyagerModel", targets: ["VoyagerModel"]),
    ],
    // Declared in local mode too (unused there), so SwiftPM keeps Package.resolved intact.
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.7"),
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
