@testable import KamomeImportKit
import XCTest

/// **A photograph taken in flight proves the leg was flown** (#224, ADR
/// 2026-10-06) — one-sided: a fix can only ever read lower or slower than the
/// truth, so it can hide a flight but never invent one.
final class AirbornePhotoTests: XCTestCase {
    /// The shipped thresholds (`import.airborne_min_altitude_m`,
    /// `import.airborne_min_speed_kmh`), pinned in `ConfigLoaderTests`.
    private let minAltitudeM = 6_000.0
    private let minSpeedKmh = 450.0

    private func photo(altitude: Double? = nil, speed: Double? = nil) -> ImportPhoto {
        ImportPhoto(
            assetId: "p", timestamp: 0, lat: 0, lon: 0,
            altitudeLowerBoundM: altitude, speedLowerBoundKmh: speed
        )
    }

    private func airborne(_ photo: ImportPhoto) -> Bool {
        photo.isAirborne(minAltitudeM: minAltitudeM, minSpeedKmh: minSpeedKmh)
    }

    func testAWindowPhotoAtCruiseIsAirborne() {
        XCTAssertTrue(airborne(photo(altitude: 10_500)))
    }

    /// The highest motorable passes sit near 5,800 m: a photograph on one is
    /// on the ground.
    func testTheHighestRoadIsNotAirborne() {
        XCTAssertFalse(airborne(photo(altitude: 5_800)))
    }

    func testCruiseSpeedIsAirborne() {
        XCTAssertTrue(airborne(photo(speed: 850)))
    }

    /// The fastest train in commercial service, the Shanghai maglev.
    func testTheFastestTrainIsNotAirborne() {
        XCTAssertFalse(airborne(photo(speed: 431)))
    }

    /// No fix, no claim — most photographs carry neither value.
    func testAPhotographWithoutAFixProvesNothing() {
        XCTAssertFalse(airborne(photo()))
    }
}
