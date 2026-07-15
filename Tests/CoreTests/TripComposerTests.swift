import KamomeTrackingEngine
import KamomeTripComposer
import XCTest

final class SimplifierTests: XCTestCase {
    func testStraightLineCollapsesToEndpoints() {
        let points = (0...100).map {
            Simplifier.Point(lat: -31.95 + Double($0) * 0.001, lon: 115.86 + Double($0) * 0.001)
        }
        let simplified = Simplifier.douglasPeucker(points, epsilonM: 15)
        XCTAssertEqual(simplified.count, 2)
        XCTAssertEqual(simplified.first, points.first)
        XCTAssertEqual(simplified.last, points.last)
    }

    func testCornerSurvivesSimplification() {
        var points = (0...50).map { Simplifier.Point(lat: -31.95 + Double($0) * 0.001, lon: 115.86) }
        points += (1...50).map { Simplifier.Point(lat: -31.90, lon: 115.86 + Double($0) * 0.001) }
        let simplified = Simplifier.douglasPeucker(points, epsilonM: 15)
        XCTAssertEqual(simplified.count, 3, "corner point must survive")
        XCTAssertTrue(simplified.contains(Simplifier.Point(lat: -31.90, lon: 115.86)))
    }

    func testPerthFixtureShrinksSubstantially() throws {
        let engine = try GPXReplay.run(fixture: "perth_margaret_river_day1.gpx")
        let drive = try XCTUnwrap(engine.segments.first { $0.mode == .drive })
        let raw = drive.points.map { Simplifier.Point(lat: $0.lat, lon: $0.lon) }
        let simplified = Simplifier.douglasPeucker(raw, epsilonM: 15)
        XCTAssertLessThan(simplified.count, raw.count / 3, "straight-ish drives should thin at least 3×")
        // Fixture legs are synthetic straight lines — collapsing to the two
        // endpoints is the *correct* extreme.
        XCTAssertGreaterThanOrEqual(simplified.count, 2)
    }
}

final class TripStatsTests: XCTestCase {
    func testStatsFromPerthReplay() throws {
        let engine = try GPXReplay.run(fixture: "perth_margaret_river_day1.gpx")
        let stats = TripStats.compute(segments: engine.segments, stops: engine.stops)

        // Fixture is ~242 km straight-line with noise (header comment).
        XCTAssertGreaterThan(stats.distanceM, 220_000)
        XCTAssertLessThan(stats.distanceM, 270_000)
        XCTAssertEqual(stats.stopCount, 4)
        XCTAssertGreaterThan(stats.driveS, stats.walkS)
        XCTAssertGreaterThan(stats.topSpeedKmh, 70)
        XCTAssertLessThan(stats.topSpeedKmh, 130)

        // Round-trips through trip.stats_json.
        let restored = TripStats.from(jsonString: stats.jsonString())
        XCTAssertEqual(restored, stats)
    }
}

final class GeocodePolicyTests: XCTestCase {
    func testThrottleAndCache() throws {
        var policy = GeocodePolicy(config: try GPXReplay.loadConfig().geocode)

        XCTAssertEqual(policy.decision(lat: -33.327, lon: 115.641, now: 100), .lookup)
        policy.recordLookup(lat: -33.327, lon: 115.641, name: "Bunbury", at: 100)

        // Same spot (within cache precision) → cached, no CLGeocoder call.
        XCTAssertEqual(policy.decision(lat: -33.3271, lon: 115.6411, now: 100.5), .cached("Bunbury"))
        // Different spot too soon → throttled with a retry hint.
        XCTAssertEqual(
            policy.decision(lat: -33.955, lon: 115.075, now: 100.5),
            .throttled(retryAfterS: 1.5)
        )
        // Different spot after the interval → lookup.
        XCTAssertEqual(policy.decision(lat: -33.955, lon: 115.075, now: 103), .lookup)
    }
}
