import KamomeConfig
@testable import KamomeRouteMatching
import XCTest

/// **A road the router found is not proof anyone drove it** (ADR 2026-10-03).
/// A flight between two airports on one continent came back as a real road,
/// passed the detour gate and was stored as one; these hold the two questions
/// asked of the road the router chose — could it be driven in the time, and
/// does any photograph witness it.
final class RouteFeasibilityTests: XCTestCase {
    /// The memberwise defaults, which `ConfigLoaderTests` pins to the shipped
    /// file, so these cases exercise the numbers the app ships.
    private let config = TrackingConfig.Matching(
        baseURL: "", chunkSize: 100, confidenceMin: 0.5, radiusM: 25, timeoutS: 10, tripBudgetS: 120,
        displayEpsilonM: 5, routeMaxDetourRatio: 2.5, routeWaypointMinSpacingM: 250, routeWaypointRadiusM: 500
    )
    private let hour = 3600.0
    private let start = 1_780_000_000.0

    // Public landmarks only (§0) — synthetic geometry, never a real trip.
    private let laxAirport = (lat: 33.9416, lon: -118.4085)
    private let denver = (lat: 39.7392, lon: -104.9903)
    private let chicago = (lat: 41.8781, lon: -87.6298)
    private let jfkAirport = (lat: 40.6413, lon: -73.7781)
    private let munich = (lat: 48.1351, lon: 11.5820)
    private let nuremberg = (lat: 49.4521, lon: 11.0767)
    private let kassel = (lat: 51.3127, lon: 9.4797)
    private let hamburg = (lat: 53.5511, lon: 9.9937)
    private let taipeiStation = (lat: 25.0478, lon: 121.5170)
    private let zuoyingStation = (lat: 22.6873, lon: 120.3076)

    private func point(_ place: (lat: Double, lon: Double), after hours: Double) -> RouteMatchPoint {
        RouteMatchPoint(ts: start + hours * hour, lat: place.lat, lon: place.lon)
    }

    private func road(_ places: [(lat: Double, lon: Double)]) -> [GeoPoint] {
        places.map { GeoPoint(lat: $0.lat, lon: $0.lon) }
    }

    /// The router's answer for the flight: overland by way of Denver and
    /// Chicago, about 4,000 km — 1.0× the straight line, so the detour gate
    /// passes it.
    private var overland: [GeoPoint] { road([laxAirport, denver, chicago, jfkAirport]) }

    /// The device case: the last photograph before the flight, the first after
    /// landing twenty-six hours on. Straight-line pace (`LegPace`) cannot call
    /// it, and only the road the router chose shows nobody drove it.
    func testAFlightAcrossConnectedLandIsNotDrivenWhenTheRoadCannotBeCoveredInTime() {
        let trace = [point(laxAirport, after: 0), point(jfkAirport, after: 26)]
        XCTAssertFalse(
            LegPace.isBeyondDriving(from: trace[0], to: trace[1], config: config),
            "precondition: the straight-line pace misses it"
        )
        XCTAssertEqual(RouteFeasibility.judge(route: overland, trace: trace, config: config), .notDriven)
    }

    /// The case the clocks cannot settle — the first photograph two days after
    /// landing. The road could have been driven in that time, but nothing
    /// along 4,000 km of it says it was: refused as road, never a crossing.
    func testALongRouteWithNoPhotographAlongItIsUnwitnessedWhateverTheClocksSay() {
        let trace = [point(laxAirport, after: 0), point(jfkAirport, after: 60)]
        XCTAssertEqual(RouteFeasibility.judge(route: overland, trace: trace, config: config), .unwitnessed)
    }

    /// **The ceiling is a day's driving, 1,200 km** (ADR 2026-10-09). About
    /// 1,280 km of road and a night either side: slow enough for the time test,
    /// so only the witness test can refuse it — and under the old ceiling
    /// (4,320 km) it was stored as road.
    func testAnUnwitnessedRoadPastADaysDrivingIsRefusedEvenWhenTheClocksAllowIt() {
        let road = road([(lat: 0, lon: 0), (lat: 0, lon: 11.5)])
        let trace = [point((lat: 0, lon: 0), after: 0), point((lat: 0, lon: 11.5), after: 30)]
        XCTAssertGreaterThan(RouteFeasibility.lengthM(road), 1_200_000, "precondition")
        XCTAssertEqual(RouteFeasibility.judge(route: road, trace: trace, config: config), .unwitnessed)
    }

    /// The other side of the line: about 1,100 km with no photograph, a long
    /// day at the wheel, is still a road.
    func testALongDaysDriveWithNoPhotographAlongItStaysARoad() {
        let road = road([(lat: 0, lon: 0), (lat: 0, lon: 9.9)])
        let trace = [point((lat: 0, lon: 0), after: 0), point((lat: 0, lon: 9.9), after: 14)]
        XCTAssertLessThan(RouteFeasibility.lengthM(road), 1_200_000, "precondition")
        XCTAssertEqual(RouteFeasibility.judge(route: road, trace: trace, config: config), .drivable)
    }

    /// A day's autobahn with photographs along it stays a road.
    func testAWitnessedDaysDriveIsDrivable() {
        let trace = [
            point(munich, after: 0), point(nuremberg, after: 2), point(kassel, after: 5), point(hamburg, after: 9)
        ]
        XCTAssertEqual(
            RouteFeasibility.judge(route: road([munich, nuremberg, kassel, hamburg]), trace: trace, config: config),
            .drivable
        )
    }

    /// Fast, and still not judged a flight: 600 km of road in five hours with
    /// the camera clock an hour behind. The clock allowance is what keeps a
    /// hard drive on the ground.
    func testAFastDriveWithAClockAnHourOffStaysARoad() {
        let trace = [point(munich, after: 0), point(nuremberg, after: 1), point(hamburg, after: 4)]
        XCTAssertEqual(
            RouteFeasibility.judge(route: road([munich, nuremberg, kassel, hamburg]), trace: trace, config: config),
            .drivable
        )
    }

    /// High-speed rail, routed as road the way every imported leg is: 290 km
    /// in ninety minutes stays under the ceiling, so no plane flies over
    /// Taiwan's west coast.
    func testHighSpeedRailIsNotFlown() {
        let trace = [point(taipeiStation, after: 0), point(zuoyingStation, after: 1.5)]
        XCTAssertEqual(
            RouteFeasibility.judge(route: road([taipeiStation, zuoyingStation]), trace: trace, config: config),
            .drivable
        )
    }

    /// The road is shared between photographs by the straight line between
    /// them: 1 : 3 of 500 km puts 375 km in the longer gap.
    func testTheUnwitnessedStretchIsTheRoadsShareOfTheLongestGap() {
        let origin = (lat: 0.0, lon: 0.0)
        let trace = [
            point(origin, after: 0), point((lat: 0.0, lon: 1.0), after: 1), point((lat: 0.0, lon: 4.0), after: 2)
        ]
        XCTAssertEqual(RouteFeasibility.longestUnwitnessedM(routedM: 500_000, trace: trace), 375_000, accuracy: 1)
    }

    /// Photographs that all sit on one spot witness nothing: the whole road is
    /// one stretch.
    func testPhotographsOnOneSpotLeaveTheWholeRouteUnwitnessed() {
        let trace = [point(munich, after: 0), point(munich, after: 1)]
        XCTAssertEqual(RouteFeasibility.longestUnwitnessedM(routedM: 1_000, trace: trace), 1_000)
    }
}
