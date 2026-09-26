// swift-tools-version: 5.10
import PackageDescription

// Pure logic for Oasis. Foundation only, so it builds and tests on Linux.
let package = Package(
    name: "OasisCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OasisCore", targets: ["OasisCore"]),
    ],
    targets: [
        .target(
            name: "OasisCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "OasisCoreTests",
            dependencies: ["OasisCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
