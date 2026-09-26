// swift-tools-version: 5.10
import PackageDescription

// Pure logic for WaterFinder. Foundation only, so it builds and tests on Linux.
let package = Package(
    name: "WaterFinderCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaterFinderCore", targets: ["WaterFinderCore"]),
    ],
    targets: [
        .target(
            name: "WaterFinderCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "WaterFinderCoreTests",
            dependencies: ["WaterFinderCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
