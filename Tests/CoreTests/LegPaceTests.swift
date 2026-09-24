import KamomeConfig
@testable import KamomeRouteMatching
import XCTest

/// The offline half of the crossing verdict (ADR 2026-09-24 (e)): a leg covered
/// faster than any drive averages is a crossing, judged on the phone — and a
/// clock that jumped a time zone must never be what makes it one.
final class LegPaceTests: XCTestCase {
    /// The memberwise defaults, which `ConfigLoaderTests` pins to the shipped
    /// file, so these cases exercise the numbers the app ships.
    private let config = TrackingConfig.Matching(
        baseURL: "", chunkSize: 100, confidenceMin: 0.5, radiusM: 25, timeoutS: 10, tripBudgetS: 120,
        displayEpsilonM: 5, routeMaxDetourRatio: 2.5, routeWaypointMinSpacingM: 250, routeWaypointRadiusM: 500
    )
    private let hour = 3600.0
    private let start = 1_780_000_000.0

    // Public landmarks only (§0).
    private let taoyuanAirport = (lat: 25.0777, lon: 121.2328)
    private let noiBaiAirport = (lat: 21.2187, lon: 105.8042)
    private let taipeiStation = (lat: 25.0478, lon: 121.5170)
    private let zuoyingStation = (lat: 22.6873, lon: 120.3076)

    private func point(_ place: (lat: Double, lon: Double), after hours: Double) -> RouteMatchPoint {
        RouteMatchPoint(ts: start + hours * hour, lat: place.lat, lon: place.lon)
    }

    /// The Vietnam film's opening leg, as a flight looks in a photo library:
    /// the last Taiwan photograph at the airport, the first in Hanoi five hours on.
    func testAFlightFromTaiwanToVietnamIsBeyondDriving() {
        XCTAssertTrue(LegPace.isBeyondDriving(
            from: point(taoyuanAirport, after: 0), to: point(noiBaiAirport, after: 5), config: config
        ))
    }

    /// One-sided: the same flight with a night in between proves nothing, and
    /// is left to routing rather than guessed at.
    func testASlowLegProvesNothing() {
        XCTAssertFalse(LegPace.isBeyondDriving(
            from: point(taoyuanAirport, after: 0), to: point(noiBaiAirport, after: 12), config: config
        ))
    }

    /// High-speed rail is fast over land. At 290 km in 90 minutes it stays
    /// under the ceiling once the clock allowance is added, so no plane
    /// flies over Taiwan's west coast.
    func testHighSpeedRailIsNotFlown() {
        XCTAssertFalse(LegPace.isBeyondDriving(
            from: point(taipeiStation, after: 0), to: point(zuoyingStation, after: 1.5), config: config
        ))
    }

    /// A short hop is never judged by pace, however fast it looks: one stale
    /// EXIF fix could fake it.
    func testAShortLegIsNeverJudged() {
        let near = (lat: taoyuanAirport.lat + 0.5, lon: taoyuanAirport.lon)
        XCTAssertFalse(LegPace.isBeyondDriving(
            from: point(taoyuanAirport, after: 0), to: point(near, after: 0), config: config
        ))
    }

    /// **The time-zone case** (Chiu 2026-09-24). A real drive of 777 km in six
    /// hours, where the arriving photo's clock reads two hours early. Its raw
    /// pace is over the ceiling, and the zone allowance brings it back under.
    func testAClockThatJumpedAZoneDoesNotFakeAFlight() {
        let west = (lat: 10.0, lon: 100.0), east = (lat: 10.0, lon: 107.1)
        let from = point(west, after: 0), to = point(east, after: 6 - 2)
        let rawKmh = 777.0 / 4
        XCTAssertGreaterThan(rawKmh, config.crossingPaceMinKmh, "without the allowance this would fly")
        XCTAssertFalse(LegPace.isBeyondDriving(from: from, to: to, config: config))
    }

    /// The allowance grows an hour per 15° of longitude on top of the margin,
    /// and a leg over the antimeridian gets a whole calendar day.
    func testTheClockAllowanceFollowsLongitudeAndTheDateLine() {
        let allowance = LegPace.clockAllowanceS(
            from: point((lat: 0, lon: 0), after: 0), to: point((lat: 0, lon: 30), after: 0), config: config
        )
        XCTAssertEqual(allowance, 2 * hour + config.crossingPaceClockMarginS, accuracy: 1)

        let fiji = (lat: -18.14, lon: 178.44), samoa = (lat: -13.83, lon: -171.77)
        let overTheLine = LegPace.clockAllowanceS(
            from: point(fiji, after: 0), to: point(samoa, after: 0), config: config
        )
        XCTAssertEqual(overTheLine, (360 - 350.21) / 15 * hour + config.crossingPaceClockMarginS + 24 * hour, accuracy: 1)
    }
}
