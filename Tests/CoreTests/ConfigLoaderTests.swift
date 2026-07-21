import KamomeConfig
import XCTest

final class ConfigLoaderTests: XCTestCase {
    /// Repo-root Config/TrackingConfig.json, located relative to this source file
    /// so the test works in both `swift test` and xcodebuild runs.
    private var configURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/CoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Config/TrackingConfig.json")
    }

    func testLoadsShippedConfigWithSpecDefaults() throws {
        let config = try TrackingConfigLoader.load(contentsOf: configURL)

        XCTAssertEqual(config.schemaVersion, 1)
        // Defaults named in the spec (§2.3, §4.1, §4.2, §4.4, §4.5).
        XCTAssertEqual(config.segmentation.modeConfirmS, 60)
        XCTAssertEqual(config.segmentation.speedTransitMinKmh, 130)
        XCTAssertEqual(config.dwell.windowS, 180)
        XCTAssertEqual(config.dwell.radiusM, 80)
        XCTAssertEqual(config.dwell.regionRadiusM, 150)
        // Trip-end stop derivation (ADR 2026-07-18).
        XCTAssertEqual(config.dwell.gapMinS, 300)
        XCTAssertEqual(config.dwell.visitMinS, 300)
        XCTAssertEqual(config.dwell.visitReturnRadiusM, 300)
        XCTAssertEqual(config.simplify.epsilonM, 15)
        // Map matching (§4.4, P3.5): disabled until the OSRM server exists.
        XCTAssertEqual(config.matching.baseURL, "")
        XCTAssertEqual(config.matching.chunkSize, 100)
        XCTAssertEqual(config.matching.confidenceMin, 0.5)
        XCTAssertEqual(config.matching.radiusM, 25)
        XCTAssertEqual(config.matching.timeoutS, 10)
        XCTAssertEqual(config.matching.displayEpsilonM, 5)
        XCTAssertEqual(config.sampling.vehicles.car.fast.distanceFilterM, 50)
        XCTAssertEqual(config.sampling.vehicles.car.slow.distanceFilterM, 20)
        XCTAssertEqual(config.sampling.vehicles.car.fastMinKmh, 20)
        XCTAssertEqual(config.sampling.walk.distanceFilterM, 10)
        XCTAssertEqual(config.export.targetDurationS, 30)
        XCTAssertEqual(config.export.maxHoldFraction, 0.5)
        // Frame render tunables (§4.5 step 2).
        XCTAssertEqual(config.export.frameWidthPx, 1080)
        XCTAssertEqual(config.export.frameHeightPx, 1920)
        XCTAssertEqual(config.export.cameraSpanM, 1500)
        XCTAssertEqual(config.export.keyframeIntervalFrames, 15)
        XCTAssertEqual(config.export.titleCardS, 2.5)
        XCTAssertEqual(config.export.endCardS, 3.0)
        XCTAssertEqual(config.export.videoBitrateMbps, 5)
        XCTAssertEqual(config.filter.maxHAccM, 50)
        XCTAssertEqual(config.filter.speedMaxHAccM, 25)
        // Phantom-trip guard (ADR 2026-07-16).
        XCTAssertEqual(config.trip.minDurationS, 60)
        XCTAssertEqual(config.trip.minDistanceM, 100)
        // Photo-EXIF import clustering (§4.7, Replay MVP) — prototype defaults.
        XCTAssertEqual(config.photoImport.stopRadiusM, 4000)
        XCTAssertEqual(config.photoImport.stopSplitGapS, 10_800)
        XCTAssertEqual(config.photoImport.minPhotosPerStop, 2)
        XCTAssertEqual(config.photoImport.deckMinPhotos, 3)
        XCTAssertEqual(config.photoImport.deckMaxPhotos, 8)
        XCTAssertEqual(config.photoImport.defaultRangeDays, 7)
    }

    func testMissingKeyFailsLoudlyNamingTheKey() throws {
        var json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: configURL)
        ) as? [String: Any] ?? [:]
        var dwell = json["dwell"] as? [String: Any] ?? [:]
        dwell.removeValue(forKey: "radius_m")
        json["dwell"] = dwell
        let mutated = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try TrackingConfigLoader.load(from: mutated)) { error in
            let message = String(describing: error)
            XCTAssertTrue(message.contains("dwell.radius_m"), "error should name the key, got: \(message)")
        }
    }

    func testGarbageInputFailsLoudly() {
        XCTAssertThrowsError(try TrackingConfigLoader.load(from: Data("not json".utf8)))
    }
}
