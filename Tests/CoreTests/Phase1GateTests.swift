import KamomeTrackingEngine
import XCTest

/// Spec §7 Phase 1 gates, asserted against the real engine via GPX replay.
final class Phase1GateTests: XCTestCase {
    /// Gate: exactly 4 stops (±0), ≥ 2 drive segments, ≥ 2 walk segments.
    func testPerthMargaretRiverDay1() throws {
        let engine = try GPXReplay.run(fixture: "perth_margaret_river_day1.gpx")

        let drives = engine.segments.filter { $0.mode == .drive }
        let walks = engine.segments.filter { $0.mode == .walk }

        XCTAssertEqual(engine.stops.count, 4, "stops: \(describe(engine))")
        XCTAssertGreaterThanOrEqual(drives.count, 2, "drive segments: \(describe(engine))")
        XCTAssertGreaterThanOrEqual(walks.count, 2, "walk segments: \(describe(engine))")
        XCTAssertEqual(engine.state, .completed)
    }

    /// Gate: the mode-flapping torture test produces ≤ 1 spurious segment.
    /// The fixture is one continuous walk, so anything beyond one walk
    /// segment is spurious.
    func testCityWalkFlappingProducesAtMostOneSpuriousSegment() throws {
        let engine = try GPXReplay.run(fixture: "city_walk_flapping.gpx")

        let spurious = engine.segments.count - 1
        XCTAssertLessThanOrEqual(spurious, 1, describe(engine))
        XCTAssertEqual(engine.segments.first?.mode, .walk, describe(engine))
        XCTAssertTrue(engine.stops.isEmpty, "traffic lights must not become stops: \(describe(engine))")
    }

    /// §1.7: the fixture's synthetic 140 km/h rail leg must classify as
    /// transit via the sustained-speed heuristic.
    func testHuandaoDetectsTransitLeg() throws {
        let engine = try GPXReplay.run(fixture: "taiwan_huandao_9days.gpx")

        let transits = engine.segments.filter { $0.mode == .transit }
        XCTAssertGreaterThanOrEqual(transits.count, 1, describe(engine))
    }

    /// §1.7: with the scooter vehicle selected, automotive-speed movement is
    /// labeled scooter, not drive.
    func testScooterVehicleLabelsFastSegmentsAsScooter() throws {
        let engine = try GPXReplay.run(fixture: "perth_margaret_river_day1.gpx", vehicle: .scooter)

        XCTAssertGreaterThanOrEqual(engine.segments.filter { $0.mode == .scooter }.count, 2, describe(engine))
        XCTAssertTrue(engine.segments.allSatisfy { $0.mode != .drive }, describe(engine))
    }

    private func describe(_ engine: TrackingEngine) -> String {
        let t0 = engine.segments.first?.startedAt ?? 0
        let segments = engine.segments
            .map { segment in
                let duration = Int((segment.endedAt ?? 0) - segment.startedAt)
                return "\(segment.mode.rawValue)(+\(Int(segment.startedAt - t0))s, \(duration)s, \(segment.points.count)pts)"
            }
            .joined(separator: ", ")
        let stops = engine.stops
            .map { "(+\(Int($0.arrivedAt - t0))s..+\(Int(($0.departedAt ?? 0) - t0))s)" }
            .joined(separator: ", ")
        return "segments=[\(segments)] stops=[\(stops)]"
    }
}
