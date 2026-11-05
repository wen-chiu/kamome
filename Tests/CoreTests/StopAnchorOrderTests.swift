@testable import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// **A stop's scene plays where the trip was when it happened** (#349): a
/// route that passes a place twice anchors the later stop there at the later
/// pass, never back at the first.
///
/// Synthetic geometry near a public place (`CLAUDE.md` §0).
final class StopAnchorOrderTests: XCTestCase {
    typealias Point = CameraPath.Point

    private let hotel = Point(lat: 38.72, lon: -9.14)

    /// `count` vertices from `start` to `end`, both ends included.
    private func line(_ start: Point, _ end: Point, count: Int = 11) -> [Point] {
        (0..<count).map { step in
            let fraction = Double(step) / Double(count - 1)
            return Point(lat: start.lat + (end.lat - start.lat) * fraction, lon: start.lon + (end.lon - start.lon) * fraction)
        }
    }

    /// Legs joined end to end, the way `RecapTrip.route` concatenates them.
    private func route(_ legs: [[Point]]) -> [Point] {
        legs.flatMap { $0 }
    }

    private func anchors(_ route: [Point], _ stops: [Point]) -> [(stopIndex: Int, distanceM: Double)] {
        CameraPath.stopAnchors(route: route, cumulativeM: CameraPath.cumulativeDistancesM(route), stops: stops)
    }

    private func assertInOrder(
        _ anchors: [(stopIndex: Int, distanceM: Double)], count: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(anchors.map(\.stopIndex), Array(0..<count), "every stop, in the order it happened", file: file, line: line)
        let distances = anchors.map(\.distanceM)
        XCTAssertEqual(distances, distances.sorted(), "ordered along the route", file: file, line: line)
    }

    func testALoopEndsOnTheLastPassNotTheFirst() {
        let east = Point(lat: hotel.lat, lon: hotel.lon + 0.4)
        let north = Point(lat: hotel.lat + 0.4, lon: hotel.lon + 0.2)
        let path = route([line(hotel, east), line(east, north), line(north, hotel)])
        let result = anchors(path, [hotel, east, north, hotel])

        assertInOrder(result, count: 4)
        XCTAssertEqual(result[3].distanceM, CameraPath.cumulativeDistancesM(path).last ?? 0, accuracy: 1,
                       "back where it began is the end of the film, not its second scene")
    }

    func testAnOutAndBackPlaysTheWayBackOnTheWayBack() {
        let middle = Point(lat: hotel.lat + 0.6, lon: hotel.lon + 0.1)
        let far = Point(lat: hotel.lat + 1.2, lon: hotel.lon + 0.2)
        let path = route([line(hotel, middle), line(middle, far), line(far, middle), line(middle, hotel)])
        let result = anchors(path, [hotel, middle, far, middle, hotel])

        assertInOrder(result, count: 5)
        XCTAssertGreaterThan(result[3].distanceM, result[2].distanceM, "the middle, on the way back, after the far end")
    }

    func testAOneHotelTripPlaysEachNightAfterItsDay() {
        let trips = [Point(lat: 38.80, lon: -9.38), Point(lat: 38.70, lon: -9.42), Point(lat: 38.57, lon: -7.91)]
        let path = route(trips.flatMap { [line(hotel, $0), line($0, hotel)] })
        let stops = [hotel] + trips.flatMap { [$0, hotel] }
        let result = anchors(path, stops)

        assertInOrder(result, count: stops.count)
    }

    /// The other half of the contract: a trip that never comes back anchors
    /// exactly where the nearest-vertex search did, so its film does not move.
    func testATripThatNeverRevisitsAnchorsAtItsNearestVertices() {
        let path = route([
            line(hotel, Point(lat: 39.2, lon: -8.9)),
            line(Point(lat: 39.2, lon: -8.9), Point(lat: 39.6, lon: -8.2), count: 23),
            line(Point(lat: 39.6, lon: -8.2), Point(lat: 40.2, lon: -8.4), count: 17)
        ])
        // Off the line by a few hundred metres, the way a photo centroid sits.
        let stops = [path[0], path[13], path[20], path[31], path[44], path[50]].map {
            Point(lat: $0.lat + 0.003, lon: $0.lon - 0.002)
        }
        let cumulative = CameraPath.cumulativeDistancesM(path)
        let nearest = stops.map { stop in
            cumulative[path.indices.min { lhs, rhs in
                Geo.distanceM(latA: stop.lat, lonA: stop.lon, latB: path[lhs].lat, lonB: path[lhs].lon)
                    < Geo.distanceM(latA: stop.lat, lonA: stop.lon, latB: path[rhs].lat, lonB: path[rhs].lon)
            } ?? 0]
        }

        XCTAssertEqual(anchors(path, stops).map(\.distanceM), nearest)
    }

    func testNoStopsAnchorNothing() {
        XCTAssertTrue(anchors(line(hotel, Point(lat: 39, lon: -9)), []).isEmpty)
    }
}
