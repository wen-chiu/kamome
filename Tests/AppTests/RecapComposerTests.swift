@testable import Kamome
import KamomeExportEngine
import KamomePersistence
import KamomeRouteMatching
import KamomeTripComposer
import XCTest

/// S5 content mapping: trip records → recap cards. Copy is localized, so
/// assertions check structure (numbers, presence, fallbacks), not wording.
final class RecapComposerTests: XCTestCase {
    private let tripStart = 1_752_600_000.0

    private func trip(daysLong: Double = 1) -> TripRecord {
        TripRecord(
            id: "trip-1",
            title: "Perth Loop",
            startedAt: tripStart,
            endedAt: tripStart + daysLong * 86_400,
            status: "completed",
            statsJson: #"{"distance_m": 1203000, "drive_s": 11520, "walk_s": 3600, "stop_count": 2, "top_speed_kmh": 96}"#
        )
    }

    private func segment(points: [(Double, Double)]) -> (segment: SegmentRecord, points: [TrackpointRecord]) {
        let record = SegmentRecord(
            id: "seg-1", tripId: "trip-1", mode: "drive", startedAt: tripStart, endedAt: tripStart + 3600
        )
        let trackpoints = points.enumerated().map { index, point in
            TrackpointRecord(segmentId: "seg-1", ts: tripStart + Double(index), lat: point.0, lon: point.1)
        }
        return (record, trackpoints)
    }

    private func stop(
        id: String = "stop-1",
        name: String? = "紫雲巖",
        arrivedOffset: Double = 600,
        duration: Double? = 1260,
        kind: String? = "dwell"
    ) -> StopRecord {
        StopRecord(
            id: id,
            tripId: "trip-1",
            lat: -32.0,
            lon: 115.75,
            arrivedAt: tripStart + arrivedOffset,
            departedAt: duration.map { tripStart + arrivedOffset + $0 },
            name: name,
            note: nil,
            kind: kind
        )
    }

    func testContentMapsRouteStopsAndCards() throws {
        let stops = [stop(), stop(id: "stop-2", name: nil, arrivedOffset: 90_000)]
        // Middle point well off the endpoints' chord so ε=15 m keeps it.
        let route = RecapComposer.route(
            from: [segment(points: [(-32.0, 115.75), (-32.1, 115.90), (-32.2, 115.77)])],
            epsilonM: 15, matchedEpsilonM: 5
        )
        let recap = try XCTUnwrap(RecapComposer.trip(
            trip: trip(daysLong: 2),
            route: route,
            stops: stops,
            stats: TripStats.from(jsonString: trip().statsJson),
            photosByStop: [:]
        ))

        XCTAssertEqual(recap.route.count, 3)
        XCTAssertEqual(recap.stops.count, 2)
        XCTAssertEqual(recap.stops[0].name, "紫雲巖")
        XCTAssertFalse(recap.stops[1].name.isEmpty, "unnamed stop must get the localized fallback")
        XCTAssertEqual(recap.title, "Perth Loop")
        XCTAssertTrue(recap.subtitle.contains("1203"), "subtitle carries distance, got: \(recap.subtitle)")
        XCTAssertEqual(recap.statsLines.count, 2)
        // localizedStringWithFormat groups digits ("1,203") per locale.
        let distanceLine = recap.statsLines[0].replacingOccurrences(of: ",", with: "")
        XCTAssertTrue(distanceLine.contains("1203"), "distance km in the stats line, got: \(recap.statsLines[0])")
        XCTAssertTrue(recap.statsLines[0].contains("2"), "stop count in the distance line")
        XCTAssertTrue(recap.statsLines[1].contains("3.2"), "drive hours with one decimal")
        XCTAssertFalse(recap.callToAction.isEmpty)
    }

    func testDegenerateRouteYieldsNoTrip() {
        XCTAssertNil(RecapComposer.trip(
            trip: trip(),
            route: RecapComposer.route(from: [segment(points: [(-32.0, 115.75)])], epsilonM: 15, matchedEpsilonM: 5),
            stops: [],
            stats: nil,
            photosByStop: [:]
        ))
    }

    func testDayLabelsUseS3DayMath() {
        // Same-day arrival → day 1; 25 h in → day 2.
        XCTAssertTrue(RecapComposer.dayLabel(for: tripStart + 600, tripStartedAt: tripStart).contains("1"))
        XCTAssertTrue(RecapComposer.dayLabel(for: tripStart + 90_000, tripStartedAt: tripStart).contains("2"))
    }

    func testWalkVisitGetsDetailLineOthersDoNot() throws {
        // 21 min walk visit → detail with the minute count.
        let visit = stop(duration: 1260, kind: "walk_visit")
        let detail = try XCTUnwrap(RecapComposer.walkDetail(for: visit))
        XCTAssertTrue(detail.contains("21"))

        // Dwell, legacy "auto", missing kind, open-ended visit: no line.
        XCTAssertNil(RecapComposer.walkDetail(for: stop(kind: "dwell")))
        XCTAssertNil(RecapComposer.walkDetail(for: stop(kind: "auto")))
        XCTAssertNil(RecapComposer.walkDetail(for: stop(kind: nil)))
        XCTAssertNil(RecapComposer.walkDetail(for: stop(duration: nil, kind: "walk_visit")))
    }

    func testStopPhotosComeFromProvidedRefs() throws {
        let recap = try XCTUnwrap(RecapComposer.trip(
            trip: trip(),
            route: RecapComposer.route(
                from: [segment(points: [(-32.0, 115.75), (-32.1, 115.76)])], epsilonM: 15, matchedEpsilonM: 5
            ),
            stops: [stop()],
            stats: nil,
            photosByStop: ["stop-1": [.asset("asset-a"), .asset("asset-b")]]
        ))
        // Refs pass through untouched — data layer points, never loads.
        XCTAssertEqual(recap.stops[0].photos, [.asset("asset-a"), .asset("asset-b")])
    }

    func testRouteSimplifiesDenseCollinearRuns() {
        // 500 straight-line points → ε=15 m keeps only the endpoints, so an
        // 8-day trip's stroke cost stays inside the §4.5 render budget.
        let dense = (0..<500).map { (-32.0 + Double($0) * 0.0001, 115.75) }
        let route = RecapComposer.route(from: [segment(points: dense)], epsilonM: 15, matchedEpsilonM: 5)
        XCTAssertGreaterThanOrEqual(route.count, 2)
        XCTAssertLessThan(route.count, 10, "collinear run must collapse")
    }

    func testMatchedSegmentUsesSnappedGeometryOverRawPoints() {
        // Raw trace cuts the corner; the stored matched polyline follows it.
        let snapped = [
            GeoPoint(lat: -32.00, lon: 115.75),
            GeoPoint(lat: -32.05, lon: 115.85),
            GeoPoint(lat: -32.20, lon: 115.77)
        ]
        var matched = segment(points: [(-32.0, 115.75), (-32.2, 115.77)])
        matched.segment.matchedPolyline = EncodedPolyline.encode(snapped)

        let route = RecapComposer.route(from: [matched], epsilonM: 15, matchedEpsilonM: 5)
        XCTAssertEqual(route.count, 3, "snapped geometry must replace the raw 2-point chord")
        XCTAssertEqual(route[1].lat, -32.05, accuracy: 0.0001)
        XCTAssertEqual(route[1].lon, 115.85, accuracy: 0.0001)
    }

    func testDegenerateMatchedPolylineFallsBackToRawPoints() {
        // A 1-point (or corrupt) stored polyline must never erase the route.
        var matched = segment(points: [(-32.0, 115.75), (-32.1, 115.90), (-32.2, 115.77)])
        matched.segment.matchedPolyline = EncodedPolyline.encode([GeoPoint(lat: -32.0, lon: 115.75)])

        let route = RecapComposer.route(from: [matched], epsilonM: 15, matchedEpsilonM: 5)
        XCTAssertEqual(route.count, 3, "raw points are the fallback")
    }

    func testShareURLEncodesTripId() {
        XCTAssertEqual(RecapComposer.shareURLString(tripId: "abc-123"), "kamome://route/abc-123")
    }
}
