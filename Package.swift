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
        .library(name: "KamomeTripComposer", targets: ["KamomeTripComposer"]),
        .library(name: "KamomeExportEngine", targets: ["KamomeExportEngine"]),
        .library(name: "KamomeRouteMatching", targets: ["KamomeRouteMatching"]),
        .library(name: "KamomeImportKit", targets: ["KamomeImportKit"]),
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
        .target(
            name: "KamomeTripComposer",
            dependencies: ["KamomeConfig", "KamomeTrackingEngine"],
            path: "Core/TripComposer"
        ),
        // Ships the vehicle artwork (`Resources/Vehicles`), specified by the
        // README beside it. Code-drawn vehicles hit a quality ceiling (Chiu
        // 2026-07-25), so subjects are raster assets; the vector markers remain
        // as the last-resort fallback. Still SDK-free and deterministic.
        //
        // **`.copy`, not `.process`.** Processing *flattens* the tree, so
        // `car-red/n.png` and any future `car-blue/n.png` would collide on one
        // `n.png` — with the winner decided by the build system rather than by
        // the manifest. One folder is one subject, so the folder structure is
        // load-bearing and has to reach the bundle intact.
        .target(
            name: "KamomeExportEngine",
            dependencies: ["KamomeConfig", "KamomeTrackingEngine"],
            path: "Core/ExportEngine",
            // No `exclude:` for `.DS_Store` — it was tried and does not work.
            // `.copy` is verbatim, and excluded paths inside a copied directory
            // still reach the bundle (measured 2026-08-17). The strip happens
            // after the build instead; see `postBuildScripts` in `project.yml`.
            resources: [.copy("Resources/Vehicles")]
        ),
        .target(
            name: "KamomeRouteMatching",
            // KamomeTrackingEngine for `Geo` only — the same reuse
            // KamomeExportEngine makes, rather than a third haversine.
            dependencies: ["KamomeConfig", "KamomeTrackingEngine"],
            path: "Core/RouteMatching"
        ),
        // Pure photo-EXIF import clustering (spec §4.7). No PhotoKit/GRDB — the
        // adapters live in the app; this stays deterministically testable.
        .target(
            name: "KamomeImportKit",
            path: "Core/ImportKit"
        ),
        .testTarget(
            name: "KamomeCoreTests",
            dependencies: [
                "KamomePersistence",
                "KamomeConfig",
                "KamomeTrackingEngine",
                "KamomeTripComposer",
                "KamomeExportEngine",
                "KamomeRouteMatching",
                "KamomeImportKit",
            ],
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
