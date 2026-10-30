@testable import Kamome
import KamomePersistence
import XCTest

/// A trip rebuilt from photographs draws only the route between its stops
/// (Chiu, 2026-10-30): a deleted transit stop takes its legs off the map and
/// out of the film.
final class TripRouteTests: XCTestCase {
    private let start = 1_752_600_000.0

    private func trip(source: TripSource) -> TripRecord {
        TripRecord(
            id: "trip-1", title: "", startedAt: start, endedAt: start + 40_000,
            status: "completed", source: source.rawValue
        )
    }

    private func leg(_ id: String, from: Double, to: Double) -> TripRoute.Leg {
        let segment = SegmentRecord(
            id: id, tripId: "trip-1", mode: "unknown",
            startedAt: start + from, endedAt: start + to, source: SegmentSource.exif.rawValue
        )
        return (segment, [
            TrackpointRecord(segmentId: id, ts: start + from, lat: 25.0, lon: 55.0),
            TrackpointRecord(segmentId: id, ts: start + to, lat: 41.8, lon: 12.2)
        ])
    }

    private func stop(_ id: String, at: Double, until: Double?) -> StopRecord {
        StopRecord(
            id: id, tripId: "trip-1", lat: 41.8, lon: 12.2,
            arrivedAt: start + at, departedAt: until.map { start + $0 }
        )
    }

    /// An import as the clusterer stores it: a loose photograph, then
    /// transit → airport → city → town, one leg into each and one beyond the last.
    private var legs: [TripRoute.Leg] {
        [
            leg("stray-to-transit", from: 0, to: 1_000),
            leg("transit-to-airport", from: 2_000, to: 20_000),
            leg("airport-to-city", from: 21_000, to: 22_000),
            leg("city-to-town", from: 23_000, to: 30_000),
            leg("town-to-stray", from: 31_000, to: 32_000)
        ]
    }

    private let transit: (Double, Double) = (1_000, 2_000)

    private func ids(_ legs: [TripRoute.Leg]) -> [String] { legs.map(\.segment.id) }

    func testDeletingTheTransitStopTakesItsFlightOff() {
        let kept = [
            stop("airport", at: 20_000, until: 21_000),
            stop("city", at: 22_000, until: 23_000),
            stop("town", at: 30_000, until: 31_000)
        ]
        XCTAssertEqual(
            ids(TripRoute.legs(trip: trip(source: .importedPhotos), segments: legs, stops: kept)),
            ["airport-to-city", "city-to-town"]
        )
    }

    func testWithTheTransitStopKeptItsFlightStays() {
        let all = [
            stop("transit", at: transit.0, until: transit.1),
            stop("airport", at: 20_000, until: 21_000),
            stop("city", at: 22_000, until: 23_000),
            stop("town", at: 30_000, until: 31_000)
        ]
        XCTAssertEqual(
            ids(TripRoute.legs(trip: trip(source: .importedPhotos), segments: legs, stops: all)),
            ["transit-to-airport", "airport-to-city", "city-to-town"]
        )
    }

    /// A stop deleted between two kept ones: the road through it still leads
    /// to a place the trip has.
    func testAMiddleStopDeletedKeepsTheRouteThroughIt() {
        let kept = [stop("airport", at: 20_000, until: 21_000), stop("town", at: 30_000, until: 31_000)]
        XCTAssertEqual(
            ids(TripRoute.legs(trip: trip(source: .importedPhotos), segments: legs, stops: kept)),
            ["airport-to-city", "city-to-town"]
        )
    }

    func testARecordingKeepsEveryLeg() {
        let kept = [stop("airport", at: 20_000, until: 21_000), stop("town", at: 30_000, until: 31_000)]
        XCTAssertEqual(
            ids(TripRoute.legs(trip: trip(source: .recorded), segments: legs, stops: kept)), ids(legs)
        )
    }

    /// One stop has nothing between it and another; the film still needs a line.
    func testFewerThanTwoStopsKeepsEveryLeg() {
        let imported = trip(source: .importedPhotos)
        XCTAssertEqual(
            ids(TripRoute.legs(trip: imported, segments: legs, stops: [stop("city", at: 22_000, until: 23_000)])),
            ids(legs)
        )
        XCTAssertEqual(ids(TripRoute.legs(trip: imported, segments: legs, stops: [])), ids(legs))
    }

    /// A last stop still open (no departure) ends the route at its arrival.
    func testAnOpenLastStopEndsTheRouteAtItsArrival() {
        let kept = [stop("airport", at: 20_000, until: 21_000), stop("town", at: 30_000, until: nil)]
        XCTAssertEqual(
            ids(TripRoute.legs(trip: trip(source: .importedPhotos), segments: legs, stops: kept)),
            ["airport-to-city", "city-to-town"]
        )
    }
}
