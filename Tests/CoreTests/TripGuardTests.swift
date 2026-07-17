import KamomeConfig
import KamomeTripComposer
import XCTest

/// Phantom-trip guard (ADR 2026-07-16): a finished recording below the
/// configured duration or distance minimum is discarded, never saved.
final class TripGuardTests: XCTestCase {
    private let config = TrackingConfig.Trip(minDurationS: 60, minDistanceM: 100)

    func testTwoSecondZeroPointTripIsPhantom() {
        // The 2026-07-16 smoke drive's accidental start/stop.
        XCTAssertTrue(TripGuard.isPhantom(durationS: 2, distanceM: 0, config: config))
    }

    func testShortDurationIsPhantomEvenWithDistance() {
        XCTAssertTrue(TripGuard.isPhantom(durationS: 30, distanceM: 500, config: config))
    }

    func testShortDistanceIsPhantomEvenWithDuration() {
        // Parked with GPS wobble: long elapsed time, no real movement.
        XCTAssertTrue(TripGuard.isPhantom(durationS: 3600, distanceM: 40, config: config))
    }

    func testTripAtExactlyBothMinimumsIsKept() {
        XCTAssertFalse(TripGuard.isPhantom(durationS: 60, distanceM: 100, config: config))
    }

    func testRealTripIsKept() {
        XCTAssertFalse(TripGuard.isPhantom(durationS: 1200, distanceM: 20_000, config: config))
    }
}
