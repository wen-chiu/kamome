@testable import Kamome
import KamomeExportEngine
import KamomePersistence
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
            epsilonM: 15
        )
        let content = try XCTUnwrap(RecapComposer.content(
            trip: trip(daysLong: 2),
            route: route,
            stops: stops,
            stats: TripStats.from(jsonString: trip().statsJson),
            photosByStop: [:]
        ))

        XCTAssertEqual(content.route.count, 3)
        XCTAssertEqual(content.stops.count, 2)
        XCTAssertEqual(content.stopCards.count, 2)
        XCTAssertEqual(content.stopCards[0].name, "紫雲巖")
        XCTAssertFalse(content.stopCards[1].name.isEmpty, "unnamed stop must get the localized fallback")
        XCTAssertEqual(content.titleCard.title, "Perth Loop")
        let subtitle = content.titleCard.subtitle
        XCTAssertTrue(subtitle.contains("1203"), "subtitle carries distance, got: \(subtitle)")
        XCTAssertEqual(content.endCard.statsLines.count, 2)
        // localizedStringWithFormat groups digits ("1,203") per locale.
        let distanceLine = content.endCard.statsLines[0].replacingOccurrences(of: ",", with: "")
        XCTAssertTrue(distanceLine.contains("1203"), "distance km in the stats line, got: \(content.endCard.statsLines[0])")
        XCTAssertTrue(content.endCard.statsLines[0].contains("2"), "stop count in the distance line")
        XCTAssertTrue(content.endCard.statsLines[1].contains("3.2"), "drive hours with one decimal")
        XCTAssertFalse(content.endCard.callToAction.isEmpty)
    }

    func testDegenerateRouteYieldsNoContent() {
        XCTAssertNil(RecapComposer.content(
            trip: trip(),
            route: RecapComposer.route(from: [segment(points: [(-32.0, 115.75)])], epsilonM: 15),
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

    func testStopCardPhotoComesFromProvidedMap() throws {
        let photo = try makeSolidImage()
        let content = try XCTUnwrap(RecapComposer.content(
            trip: trip(),
            route: RecapComposer.route(from: [segment(points: [(-32.0, 115.75), (-32.1, 115.76)])], epsilonM: 15),
            stops: [stop()],
            stats: nil,
            photosByStop: ["stop-1": photo]
        ))
        XCTAssertNotNil(content.stopCards[0].photo)
    }

    func testRouteSimplifiesDenseCollinearRuns() {
        // 500 straight-line points → ε=15 m keeps only the endpoints, so an
        // 8-day trip's stroke cost stays inside the §4.5 render budget.
        let dense = (0..<500).map { (-32.0 + Double($0) * 0.0001, 115.75) }
        let route = RecapComposer.route(from: [segment(points: dense)], epsilonM: 15)
        XCTAssertGreaterThanOrEqual(route.count, 2)
        XCTAssertLessThan(route.count, 10, "collinear run must collapse")
    }

    func testShareURLEncodesTripId() {
        XCTAssertEqual(RecapComposer.shareURLString(tripId: "abc-123"), "kamome://route/abc-123")
    }

    private func makeSolidImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }
}
