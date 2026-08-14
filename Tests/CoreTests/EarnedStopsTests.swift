import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **How much film a trip's size earns** (Chiu 2026-08-14).
///
/// The three anchors below are the films Chiu watched and approved, so they are
/// acceptance criteria rather than regression bookkeeping. Everything else here
/// tests the two properties that make a reverse-derived rule survivable — it
/// cannot explode on a huge trip, and it cannot collapse on a tiny one — because
/// the parameters themselves were fitted to those same three trips, which is
/// exactly how `body_span_padding` and `tier_skip_share` were derived before both
/// failed.
final class EarnedStopsTests: XCTestCase {
    /// The **shipped** values, not a fixture config: these anchors are only
    /// meaningful against what the app actually ships. Located relative to this
    /// source file, the same way `ConfigLoaderTests` does it.
    private func shipped() throws -> TrackingConfig.Export {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
        return try TrackingConfigLoader.load(contentsOf: url).export
    }

    /// The approved films, in stops. **Iceland is 21, not 22** — the film that was
    /// published presents 21, because the direction this replaced floored a
    /// division that lands on `21.999999999999996`.
    func testTheThreeApprovedTripsEarnTheStopsTheirFilmsPresent() throws {
        let config = try shipped()
        XCTAssertEqual(StopPhotoAllocator.earnedStopCount(tripStopCount: 10, config: config), 8)
        XCTAssertEqual(StopPhotoAllocator.earnedStopCount(tripStopCount: 20, config: config), 15)
        XCTAssertEqual(StopPhotoAllocator.earnedStopCount(tripStopCount: 65, config: config), 21)
    }

    /// Growth is sub-linear: 6.5× the trip must not buy 6.5× the film.
    func testGrowthIsSubLinear() throws {
        let config = try shipped()
        let small = StopPhotoAllocator.earnedStopCount(tripStopCount: 10, config: config)
        let large = StopPhotoAllocator.earnedStopCount(tripStopCount: 65, config: config)
        XCTAssertLessThan(Double(large) / Double(small), 6.5,
                          "a 65-stop trip must not earn 6.5x the film of a 10-stop one")
        XCTAssertGreaterThan(large, small)
    }

    /// **Cannot explode.** The failure mode of every constant this repo has had to
    /// delete was unbounded behaviour on a trip it was not fitted to.
    func testAbsurdlyLargeTripsAreBoundedByTheCap() throws {
        let config = try shipped()
        for stops in [100, 500, 5_000, 100_000] {
            XCTAssertEqual(StopPhotoAllocator.earnedStopCount(tripStopCount: stops, config: config),
                           config.earnedStopsCap, "\(stops) stops")
        }
    }

    /// **Cannot collapse.** Below the reference the floor holds, and a trip with
    /// fewer stops than the floor is bounded by the stops it actually has — which
    /// `triage` applies, not the rule.
    func testTinyTripsAreBoundedByTheFloorAndByTheTripItself() throws {
        let config = try shipped()
        for stops in [1, 2, 3, 4, 9] {
            XCTAssertEqual(StopPhotoAllocator.earnedStopCount(tripStopCount: stops, config: config),
                           config.earnedStopsFloor, "\(stops) stops")
        }
        XCTAssertEqual(StopPhotoAllocator.earnedStopCount(tripStopCount: 0, config: config), 0)

        let signals = (0..<3).map { _ in StopPhotoAllocator.Signal(photoCount: 4, favoriteCount: 0) }
        let tiers = StopPhotoAllocator.triage(signals, config: config)
        XCTAssertEqual(tiers.compactMap { $0 }.count, 3, "a 3-stop trip presents 3 stops, never 8")
    }

    /// Monotonic: a bigger trip never earns a shorter film.
    func testEarnedStopsNeverDecreaseWithTripSize() throws {
        let config = try shipped()
        var previous = 0
        for stops in 1...200 {
            let earned = StopPhotoAllocator.earnedStopCount(tripStopCount: stops, config: config)
            XCTAssertGreaterThanOrEqual(earned, previous, "\(stops) stops")
            previous = earned
        }
    }

    /// The inversion's own reason for existing: **no division to floor**, so no
    /// boundary artifact. Under the old direction Iceland's 210 s evaluated to
    /// `21.999999999999996` and silently lost a stop.
    func testDurationRoundTripsThroughTheCostModelWithoutABoundaryArtifact() throws {
        let config = try shipped()
        for stops in 1...40 {
            let duration = StopPhotoAllocator.earnedDurationS(presentedStops: stops, config: config)
            let body = duration - config.openingCountryS - config.openingRegionalS
                - 2 * config.zoomTransitionS - config.endCardS
            let recovered = body * config.maxHoldFraction / StopPhotoAllocator.presentationCostS(config: config)
            XCTAssertEqual(recovered, Double(stops), accuracy: 0.001, "\(stops) stops")
        }
    }

    /// The cost model prices the **expected mix** of standard and top-tier stops
    /// (Chiu 2026-08-14). Fixtures carry no favourites, so this term is invisible
    /// on every desk render and only a real photo library exercises it.
    func testPresentationCostPricesTheExpectedTierMix() throws {
        let config = try shipped()
        let overhead = config.deckLabelLeadS + 2 * config.deckZoomS + 2 * config.subjectParkS
        let standardOnly = overhead + Double(config.tierStandardPhotos) * config.deckPhotoMinHoldS
        let worstCase = overhead + Double(config.tierTopPhotos) * config.deckPhotoMinHoldS
        let actual = StopPhotoAllocator.presentationCostS(config: config)

        XCTAssertGreaterThan(actual, standardOnly, "standard-only under-prices a library with favourites")
        XCTAssertLessThan(actual, worstCase, "worst case is unreachable — tier_top_share caps the top tier")
    }
}
