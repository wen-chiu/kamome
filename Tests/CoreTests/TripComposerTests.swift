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
        // Fixture drive legs are road-matched; long freeway straights still
        // collapse hard while real curves survive.
        XCTAssertGreaterThanOrEqual(simplified.count, 2)
    }
}

final class TripStatsTests: XCTestCase {
    func testStatsFromPerthReplay() throws {
        let engine = try GPXReplay.run(fixture: "perth_margaret_river_day1.gpx")
        let config = try GPXReplay.loadConfig()
        // Mirrors TrackingSession.end(): stats count live ∪ derived stops
        // (ADR 2026-07-18).
        let allStops = engine.stops + StopDeriver.derive(
            segments: engine.segments, engineStops: engine.stops, config: config
        )
        let stats = TripStats.compute(segments: engine.segments, stops: allStops, config: config)

        // Fixture drive legs are road-matched (~291 km by road, header
        // comment) plus ~7 km of walk loops.
        XCTAssertGreaterThan(stats.distanceM, 275_000)
        XCTAssertLessThan(stats.distanceM, 315_000)
        XCTAssertEqual(stats.stopCount, 4)
        XCTAssertGreaterThan(stats.driveS, stats.walkS)
        XCTAssertGreaterThan(stats.topSpeedKmh, 70)
        XCTAssertLessThan(stats.topSpeedKmh, 130)

        // Round-trips through trip.stats_json.
        let restored = TripStats.from(jsonString: stats.jsonString())
        XCTAssertEqual(restored, stats)
    }

    /// Regression for the 2026-07-18 drive: a 3-second GPS glitch cluster
    /// (137 m jumps, h_acc 43–49 m — inside the keep filter) carried
    /// CoreLocation speeds of 137 m/s and put 495 km/h in the stats. Glitch
    /// points are position-kept but must not count as speed evidence.
    func testGlitchClusterDoesNotInflateTopSpeed() throws {
        let config = try GPXReplay.loadConfig()
        let engine = TrackingEngine(config: config, vehicle: .car)
        let mps = 60.0 / 3.6
        let mPerDegLat = 111_320.0

        engine.start(at: 0)
        for second in stride(from: 0.0, through: 600, by: 2) {
            let isGlitch = (300...304).contains(second)
            // The glitch shears sideways off the path, exactly like the real
            // trace: position jumps ~137 m/s east for a few fixes.
            let glitchOffsetLon = isGlitch ? (second - 298) * 137.0 / mPerDegLat : 0
            engine.process(
                LocationSample(
                    ts: second,
                    lat: 25.0 + second * mps / mPerDegLat,
                    lon: 121.36 + glitchOffsetLon,
                    hAccM: isGlitch ? 45 : 5,
                    speedMps: isGlitch ? 137.4 : mps
                )
            )
        }
        engine.finish(at: 600)

        let stats = TripStats.compute(segments: engine.segments, stops: engine.stops, config: config)
        XCTAssertGreaterThan(stats.topSpeedKmh, 55, "real cruising speed should survive")
        XCTAssertLessThan(stats.topSpeedKmh, 70, "glitch cluster must not inflate top speed")
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
