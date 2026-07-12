import KamomeConfig
import KamomeTripComposer
import XCTest

/// Phase 2 gate (spec §7): photo→stop assignment — timestamp-only, GPS, and
/// conflict cases.
final class PhotoMatcherTests: XCTestCase {
    // Two stops ~2.4 km apart (Bunbury-ish), 30 min each.
    private let stopA = PhotoMatcher.Stop(id: "A", lat: -33.3270, lon: 115.6410, arrivedAt: 1_000, departedAt: 2_800)
    private let stopB = PhotoMatcher.Stop(id: "B", lat: -33.3480, lon: 115.6480, arrivedAt: 4_000, departedAt: 5_800)
    private var stops: [PhotoMatcher.Stop] { [stopA, stopB] }
    private var config: TrackingConfig.Photos!

    override func setUpWithError() throws {
        config = try GPXReplay.loadConfig().photos
    }

    func testTimestampOnlyPhotoAttachesToContainingStop() {
        let photo = PhotoMatcher.Photo(id: "p1", takenAt: 4_500) // inside B's interval
        XCTAssertEqual(PhotoMatcher.stopId(for: photo, stops: stops, tripEndedAt: 9_000, config: config), "B")
    }

    func testTimestampOnlyPhotoBetweenStopsIsRouteAttached() {
        let photo = PhotoMatcher.Photo(id: "p2", takenAt: 3_200) // driving between A and B
        XCTAssertNil(PhotoMatcher.stopId(for: photo, stops: stops, tripEndedAt: 9_000, config: config))
    }

    func testOpenEndedFinalStopUsesTripEnd() {
        let openStop = PhotoMatcher.Stop(id: "C", lat: -33.9550, lon: 115.0750, arrivedAt: 8_000, departedAt: nil)
        let photo = PhotoMatcher.Photo(id: "p3", takenAt: 8_500)
        XCTAssertEqual(
            PhotoMatcher.stopId(for: photo, stops: [openStop], tripEndedAt: 9_000, config: config),
            "C"
        )
    }

    func testGpsPhotoAttachesToNearestStopWithinRadius() {
        // ~150 m from stop A, timestamp missing entirely.
        let photo = PhotoMatcher.Photo(id: "p4", takenAt: nil, lat: -33.3283, lon: 115.6415)
        XCTAssertEqual(PhotoMatcher.stopId(for: photo, stops: stops, tripEndedAt: 9_000, config: config), "A")
    }

    func testGpsPhotoBeyondRadiusIsRouteAttached() {
        // ~1.2 km from both stops.
        let photo = PhotoMatcher.Photo(id: "p5", takenAt: nil, lat: -33.3376, lon: 115.6445)
        XCTAssertNil(PhotoMatcher.stopId(for: photo, stops: stops, tripEndedAt: 9_000, config: config))
    }

    func testConflictGpsOutranksTimestamp() {
        // Taken (by clock) during stop B, but GPS puts it at stop A —
        // e.g. camera clock skew. GPS wins (§4.3 rule order).
        let photo = PhotoMatcher.Photo(id: "p6", takenAt: 4_500, lat: -33.3272, lon: 115.6412)
        XCTAssertEqual(PhotoMatcher.stopId(for: photo, stops: stops, tripEndedAt: 9_000, config: config), "A")
    }

    func testConflictGpsFarFromAnyStopBeatsContainingInterval() {
        // Timestamp inside stop A's interval but GPS is mid-route: the photo
        // was demonstrably not taken at the stop.
        let photo = PhotoMatcher.Photo(id: "p7", takenAt: 1_500, lat: -33.3376, lon: 115.6445)
        XCTAssertNil(PhotoMatcher.stopId(for: photo, stops: stops, tripEndedAt: 9_000, config: config))
    }

    func testNoTimestampNoGpsIsRouteAttached() {
        let photo = PhotoMatcher.Photo(id: "p8", takenAt: nil)
        XCTAssertNil(PhotoMatcher.stopId(for: photo, stops: stops, tripEndedAt: 9_000, config: config))
    }
}
