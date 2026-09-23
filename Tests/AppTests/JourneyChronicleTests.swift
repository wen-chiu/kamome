@testable import Kamome
import KamomePersistence
import XCTest

/// **Reading the timeline as a life** (Chiu, 2026-09-23): which visit a journey
/// was, and how long the user was home between two. Both are claims about the
/// user's life printed as fact, so the counting rules are held here.
final class JourneyChronicleTests: XCTestCase {
    private let day = 86_400.0

    private func journey(
        _ id: String, start: Double, days: Double, country: String? = nil, code: String? = nil
    ) -> JourneySummary {
        JourneySummary(
            id: id, tripId: id, discoveryKey: nil, name: nil, fallbackTitle: id,
            startedAt: start * day, endedAt: (start + days) * day,
            photoCount: 10, stopCount: 2, coverAssetIds: [], distanceM: nil,
            legModes: [], milestones: [], provenance: .fromPhotos, filmCount: 0,
            nameLookupLat: nil, nameLookupLon: nil, isSinglePlace: false,
            countryCode: code, countryName: country
        )
    }

    func testVisitsCountUpPerCountryInTimeOrder() {
        let visits = JourneyChronicle.visits([
            journey("jp3", start: 300, days: 5, country: "Japan", code: "JP"),
            journey("vn1", start: 200, days: 5, country: "Vietnam", code: "VN"),
            journey("jp1", start: 10, days: 5, country: "Japan", code: "JP"),
            journey("jp2", start: 100, days: 5, country: "Japan", code: "JP")
        ], homeCountryCode: "TW")

        XCTAssertEqual(visits["jp1"]?.ordinal, 1)
        XCTAssertEqual(visits["jp2"]?.ordinal, 2)
        XCTAssertEqual(visits["jp3"]?.ordinal, 3)
        XCTAssertEqual(visits["vn1"], JourneyChronicle.Visit(ordinal: 1, country: "Vietnam"))
    }

    /// The 2026-09-23 screenshot: one Vietnam trip on the timeline three times,
    /// overlapping. Three rows are not three trips.
    func testOverlappingJourneysAreOneVisit() {
        let visits = JourneyChronicle.visits([
            journey("long", start: 12, days: 22, country: "Vietnam", code: "VN"),
            journey("a", start: 13, days: 4, country: "Vietnam", code: "VN"),
            journey("b", start: 13, days: 4, country: "Vietnam", code: "VN"),
            journey("later", start: 100, days: 3, country: "Vietnam", code: "VN")
        ], homeCountryCode: "TW")

        XCTAssertEqual(visits["long"]?.ordinal, 1)
        XCTAssertEqual(visits["a"]?.ordinal, 1)
        XCTAssertEqual(visits["b"]?.ordinal, 1)
        XCTAssertEqual(visits["later"]?.ordinal, 2)
    }

    func testHomeAndUnknownCountriesHaveNoVisitLine() {
        let visits = JourneyChronicle.visits([
            journey("home", start: 10, days: 3, country: "Taiwan", code: "tw"),
            journey("unnamed", start: 50, days: 3)
        ], homeCountryCode: "TW")

        XCTAssertTrue(visits.isEmpty, "\(visits)")
    }

    func testHomeDaysCountTheNightsBetween() {
        let older = journey("older", start: 10, days: 4)
        XCTAssertEqual(JourneyChronicle.homeDays(after: older, before: journey("n", start: 30, days: 2)), 15)
        XCTAssertNil(
            JourneyChronicle.homeDays(after: older, before: journey("next", start: 15, days: 2)),
            "the day after the last one is no time at home"
        )
        XCTAssertNil(
            JourneyChronicle.homeDays(after: older, before: journey("overlap", start: 12, days: 5)),
            "overlapping journeys have no gap"
        )
    }

    /// 「上次是 2025年12月（大阪）」 names the visit before, not the overlapping
    /// row of the same visit.
    func testAVisitKnowsTheOneBeforeIt() {
        let visits = JourneyChronicle.visits([
            journey("osaka", start: 10, days: 2, country: "Japan", code: "JP"),
            journey("tokyo", start: 100, days: 5, country: "Japan", code: "JP"),
            journey("tokyo-again", start: 101, days: 2, country: "Japan", code: "JP"),
            journey("kyoto", start: 300, days: 3, country: "Japan", code: "JP")
        ], homeCountryCode: "TW")

        XCTAssertNil(visits["osaka"]?.previous)
        XCTAssertEqual(visits["tokyo"]?.previous?.title, "osaka")
        XCTAssertEqual(visits["tokyo-again"]?.previous?.title, "osaka", "the same visit, so the same one before")
        XCTAssertEqual(visits["kyoto"]?.previous?.title, "tokyo")
        XCTAssertEqual(visits["kyoto"]?.previous?.startedAt, 100 * day)
    }

    // MARK: - Kilometres on the ground

    private func leg(_ id: String, mode: String, verdict: SegmentRoutability?, lat: Double)
        -> (segment: SegmentRecord, points: [TrackpointRecord]) {
        let segment = SegmentRecord(id: id, tripId: "t", mode: mode, startedAt: 0, routability: verdict?.rawValue)
        // One degree of latitude, roughly 111 km.
        let points = [
            TrackpointRecord(segmentId: id, ts: 0, lat: lat, lon: 120),
            TrackpointRecord(segmentId: id, ts: 1, lat: lat + 1, lon: 120)
        ]
        return (segment, points)
    }

    /// Chiu, 2026-09-23: 「只算地面交通」. A flight, a leg routing never answered
    /// for, and a leg of unknown mode are all left out.
    func testOnlyGroundLegsAreCounted() throws {
        let one = LegLength.meters(segment: leg("x", mode: "drive", verdict: .road, lat: 10).segment,
                                   points: leg("x", mode: "drive", verdict: .road, lat: 10).points)
        let total = try XCTUnwrap(LegLength.groundMeters([
            leg("drive", mode: "drive", verdict: .road, lat: 10),
            leg("train", mode: "transit", verdict: .implausibleRoute, lat: 20),
            leg("flight", mode: "drive", verdict: .noRoad, lat: 30),
            leg("unasked", mode: "drive", verdict: nil, lat: 40),
            leg("unknown", mode: "unknown", verdict: .road, lat: 50)
        ]))
        XCTAssertEqual(total / one, 2, accuracy: 0.01, "the drive and the train only")
    }

    func testNoGroundLegMeansNoDistance() {
        XCTAssertNil(LegLength.groundMeters([leg("flight", mode: "drive", verdict: .noRoad, lat: 30)]))
        XCTAssertNil(LegLength.groundMeters([]))
    }
}
