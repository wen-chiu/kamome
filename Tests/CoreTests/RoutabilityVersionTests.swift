import KamomePersistence
import XCTest

/// **A verdict carries the rules it was reached under** (schema v13, arch review
/// 2026-09-26). A rule change re-asks the legs whose verdict it could change by
/// bumping a number, instead of a data migration clearing rows (v7, v11).
final class RoutabilityVersionTests: XCTestCase {
    func testAVerdictStoredBeforeVersionsExistedStillHolds() {
        // Every row written before v13 has NULL; today's rules are version 1.
        let legacy = SegmentRecord(id: "s", tripId: "t", mode: "drive", startedAt: 0, routability: "no_road")
        XCTAssertEqual(legacy.routeVerdict, .noRoad)
    }

    func testAVerdictOlderThanItsRuleReadsAsNotYetAsked() {
        // A rule revised in version 2 un-answers what version 1 stored — and
        // only for that verdict.
        XCTAssertFalse(SegmentRoutability.beyondDriving.stillHolds(storedUnder: 1, lastRevised: 2))
        XCTAssertFalse(SegmentRoutability.beyondDriving.stillHolds(storedUnder: nil, lastRevised: 2))
        XCTAssertTrue(SegmentRoutability.beyondDriving.stillHolds(storedUnder: 2, lastRevised: 2))
        XCTAssertTrue(SegmentRoutability.road.stillHolds(storedUnder: 1))
    }

    /// **Version 2 raised `crossing_pace_min_kmh` to 160** (ADR 2026-09-26 (b)).
    /// A leg judged too fast to drive under 150 may not be under 160, so it is
    /// judged again; no other verdict could change, so no other leg is asked.
    func testRaisingThePaceThresholdReasksOnlyTooFastLegs() {
        let judgedAt150 = SegmentRecord(id: "a", tripId: "t", mode: "drive", startedAt: 0, routability: "beyond_driving")
        let judgedAt160 = SegmentRecord(
            id: "b", tripId: "t", mode: "drive", startedAt: 0, routability: "beyond_driving", routabilityVersion: 2
        )
        let sea = SegmentRecord(id: "c", tripId: "t", mode: "drive", startedAt: 0, routability: "no_road")
        XCTAssertNil(judgedAt150.routeVerdict, "a verdict under the 150 draft must be judged again")
        XCTAssertEqual(judgedAt160.routeVerdict, .beyondDriving)
        XCTAssertEqual(sea.routeVerdict, .noRoad, "a verdict the change cannot touch is not re-asked")
    }

    func testStoringAVerdictRecordsTheCurrentRules() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try repository.saveCompletedTrip(
            title: "T", startedAt: 0, endedAt: 60,
            segments: [TripRepository.NewSegment(mode: "drive", startedAt: 0, endedAt: 60, points: [])],
            stops: []
        )
        let segment = try XCTUnwrap(try repository.detail(tripId: tripId)?.segments.first?.segment)

        try repository.setRoutability(segmentId: segment.id, .offRoadNetwork)

        let stored = try XCTUnwrap(try repository.detail(tripId: tripId)?.segments.first?.segment)
        XCTAssertEqual(stored.routabilityVersion, SegmentRoutability.rulesVersion)
        XCTAssertEqual(stored.routeVerdict, .offRoadNetwork)
    }
}
