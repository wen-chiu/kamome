// swift-tools-version: 5.10
// KamomeCore: the non-UI core of Kamome, kept in a SwiftPM package so its
// tests also run with `swift test` (no Xcode required). The XcodeGen-generated
// app project consumes these products as a local package dependency.
import PackageDescription

let package = Package(
    name: "KamomeCore",
    defaultLocalization: "zh-Hant",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "KamomePersistence", targets: ["KamomePersistence"]),
        .library(name: "KamomeConfig", targets: ["KamomeConfig"]),
        .library(name: "KamomeTrackingEngine", targets: ["KamomeTrackingEngine"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .target(
            name: "KamomePersistence",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Core/Persistence"
        ),
        .target(
            name: "KamomeConfig",
            path: "Core/ConfigLoader"
        ),
        .target(
            name: "KamomeTrackingEngine",
            dependencies: ["KamomeConfig"],
            path: "Core/TrackingEngine"
        ),
        .testTarget(
            name: "KamomeCoreTests",
            dependencies: ["KamomePersistence", "KamomeConfig", "KamomeTrackingEngine"],
            path: "Tests/CoreTests"
        ),
        // Local-only mirror of the Phase 0 gates for machines without Xcode
        // (Command Line Tools have no XCTest). CI runs the XCTest suite.
        .executableTarget(
            name: "kamome-smoke",
            dependencies: [
                "KamomePersistence",
                "KamomeConfig",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/Smoke"
        ),
    ]
)
