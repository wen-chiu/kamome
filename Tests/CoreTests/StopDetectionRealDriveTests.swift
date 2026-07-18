import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import KamomeTripComposer
import XCTest

/// Synthetic reproductions of the 2026-07-18 drive's three stop-detection
/// failures (ADR 2026-07-18). Shapes and numbers mirror the real trip:
/// a 21-minute walk within 50 m of a temple, a 586 s sample-silence gap with
/// 21 m displacement at a 7-11, and 25 s sparse sampling that starved the
/// old boundary-sliver dwell rule.
final class StopDetectionRealDriveTests: XCTestCase {
    private let mPerDegLat = 111_320.0
    private var config: TrackingConfig!

    override func setUpWithError() throws {
        config = try GPXReplay.loadConfig()
    }

    /// Drive north at 60 km/h feeding the engine one fix every 2 s.
    private func drive(_ engine: TrackingEngine, from ts: Double, lat: Double, lon: Double, seconds: Double) -> (Double, Double) {
        let mps = 60.0 / 3.6
        var lat = lat
        var now = ts
        while now < ts + seconds {
            engine.process(LocationSample(ts: now, lat: lat, lon: lon, hAccM: 5, speedMps: mps))
            now += 2
            lat += 2 * mps / mPerDegLat
        }
        return (lat, now)
    }

    // MARK: - Parked dwell on sparse sampling (the boundary-sliver bug)

    func testParkedDwellFiresOnSparseIrregularSampling() {
        let engine = TrackingEngine(config: config, vehicle: .car)
        engine.start(at: 0)
        var (lat, now) = drive(engine, from: 0, lat: 25.0, lon: 121.36, seconds: 600)

        // Parked: sporadic fixes every 23–31 s with ≤ 12 m jitter — no fix
        // ever lands in the 1 s window-boundary sliver the old rule needed.
        var step = 0
        while engine.state == .recording, now < 1200 {
            let jitter = Double((step * 7) % 12) / mPerDegLat
            engine.process(LocationSample(ts: now, lat: lat + jitter, lon: 121.36, hAccM: 8, speedMps: 0))
            now += 23 + Double(step % 3) * 4
            step += 1
        }

        XCTAssertEqual(engine.state, .dwellPaused, "parked car with sparse fixes must dwell within the window")
        XCTAssertEqual(engine.stops.count, 1)
    }

    // MARK: - Temple: walk visit keeps the walk trace and becomes a stop

    func testWalkVisitYieldsStopAndPreservesWalkSegment() {
        let engine = TrackingEngine(config: config, vehicle: .car)
        engine.start(at: 0)
        var (lat, now) = drive(engine, from: 0, lat: 25.0, lon: 121.36, seconds: 600)
        let templeLat = lat

        // 21 minutes wandering within ~45 m: slow walk fixes every 25 s,
        // including dead-still stretches (the real trip had 180 s windows
        // with 1 m of movement — the dwell pause must NOT fire mid-walk).
        let walkEnd = now + 1260
        var step = 0
        while now < walkEnd {
            let wander = Double((step * 13) % 45) / mPerDegLat
            let still = (step % 10) < 4  // 4 of every 10 fixes: sitting still
            engine.process(LocationSample(
                ts: now,
                lat: templeLat + (still ? 0 : wander),
                lon: 121.36,
                hAccM: 10,
                speedMps: still ? 0 : 1.2
            ))
            now += 25
            step += 1
        }
        (lat, now) = drive(engine, from: now, lat: templeLat, lon: 121.36, seconds: 600)
        engine.finish(at: now)

        XCTAssertEqual(engine.stops.count, 0, "no live dwell: GPS must keep recording the walk")
        let walkSegments = engine.segments.filter { $0.mode == .walk }
        XCTAssertEqual(walkSegments.count, 1, "the walking trace is recap material and must survive")

        let derived = StopDeriver.derive(segments: engine.segments, engineStops: engine.stops, config: config)
        XCTAssertEqual(derived.count, 1, "the walk visit is a stop")
        let stop = derived[0]
        XCTAssertEqual((stop.departedAt ?? 0) - stop.arrivedAt, 1260, accuracy: 120)
        XCTAssertEqual(stop.lat, templeLat, accuracy: 100 / mPerDegLat)
    }

    /// A displaced A→B walk (car left behind, picked up down the road) never
    /// closes its loop — a segment, not a stop.
    func testLongDisplacedWalkIsNotAVisitStop() {
        let engine = TrackingEngine(config: config, vehicle: .car)
        engine.start(at: 0)
        var (lat, now) = drive(engine, from: 0, lat: 25.0, lon: 121.36, seconds: 600)

        // 12 min walking away in a straight line (~900 m), then driving on.
        let walkEnd = now + 720
        while now < walkEnd {
            engine.process(LocationSample(ts: now, lat: lat, lon: 121.36, hAccM: 10, speedMps: 1.3))
            now += 20
            lat += 20 * 1.3 / mPerDegLat
        }
        (lat, now) = drive(engine, from: now, lat: lat, lon: 121.36, seconds: 600)
        engine.finish(at: now)

        let derived = StopDeriver.derive(segments: engine.segments, engineStops: engine.stops, config: config)
        XCTAssertTrue(derived.isEmpty, "a walk that travels somewhere is a segment, not a stop")
    }

    // MARK: - 7-11: sample silence is a stop

    func testSampleSilenceGapYieldsExactlyOneStop() {
        let engine = TrackingEngine(config: config, vehicle: .car)
        engine.start(at: 0)
        var (lat, now) = drive(engine, from: 0, lat: 25.0, lon: 121.36, seconds: 600)

        // Parked at the 7-11: iOS goes silent for 586 s; the phone reappears
        // 21 m away (the real trip's numbers) and drives on.
        now += 586
        lat += 21 / mPerDegLat
        (lat, now) = drive(engine, from: now, lat: lat, lon: 121.36, seconds: 600)
        engine.finish(at: now)

        let derived = StopDeriver.derive(segments: engine.segments, engineStops: engine.stops, config: config)
        let total = engine.stops.count + derived.count
        XCTAssertEqual(total, 1, "engine (live, at departure) and deriver (gap) must not double-count")
        let stop = (engine.stops + derived)[0]
        XCTAssertEqual((stop.departedAt ?? 0) - stop.arrivedAt, 586, accuracy: 200)
    }

    /// A short red light with samples flowing must not become a stop.
    func testRedLightIsNotAStop() {
        let engine = TrackingEngine(config: config, vehicle: .car)
        engine.start(at: 0)
        var (lat, now) = drive(engine, from: 0, lat: 25.0, lon: 121.36, seconds: 600)

        // 90 s at a light with sporadic jitter fixes.
        let lightEnd = now + 90
        while now < lightEnd {
            engine.process(LocationSample(ts: now, lat: lat, lon: 121.36, hAccM: 8, speedMps: 0))
            now += 30
        }
        (lat, now) = drive(engine, from: now, lat: lat, lon: 121.36, seconds: 600)
        engine.finish(at: now)

        let derived = StopDeriver.derive(segments: engine.segments, engineStops: engine.stops, config: config)
        XCTAssertEqual(engine.stops.count + derived.count, 0)
    }
}
