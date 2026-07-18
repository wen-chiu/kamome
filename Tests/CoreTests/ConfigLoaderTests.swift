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
        XCTAssertEqual(config.simplify.epsilonM, 15)
        XCTAssertEqual(config.sampling.vehicles.car.fast.distanceFilterM, 50)
        XCTAssertEqual(config.sampling.vehicles.car.slow.distanceFilterM, 20)
        XCTAssertEqual(config.sampling.vehicles.car.fastMinKmh, 20)
        XCTAssertEqual(config.sampling.walk.distanceFilterM, 10)
        XCTAssertEqual(config.export.targetDurationS, 30)
        XCTAssertEqual(config.export.maxHoldFraction, 0.5)
        XCTAssertEqual(config.filter.maxHAccM, 50)
        XCTAssertEqual(config.filter.speedMaxHAccM, 25)
        // Phantom-trip guard (ADR 2026-07-16).
        XCTAssertEqual(config.trip.minDurationS, 60)
        XCTAssertEqual(config.trip.minDistanceM, 100)
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
