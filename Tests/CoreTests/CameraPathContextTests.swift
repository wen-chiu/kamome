import KamomeConfig
@testable import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// **An area is never framed deeper than the place it sits in allows**
/// (ADR 2026-09-24 (c), `CameraPathContext`).
///
/// Chiu, on the Miyakojima film framed area by area: the town fell to 1.9 km and
/// *「太細部的行程會不知道自己在哪裡」*. These pin the ladder that finds the place
/// an area sits in, and the floor it sets, on the **shipped** tunables.
final class CameraPathContextTests: XCTestCase {
    private static let configURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Config/TrackingConfig.json")

    private func shipped() throws -> TrackingConfig.Export {
        try TrackingConfigLoader.load(contentsOf: Self.configURL).export
    }

    /// A ~1.3 km loop of 12 steps, closed — the same town `CameraPathAreasTests` drives.
    private func town(lat: Double, lon: Double) -> [CameraPath.Point] {
        (0...12).map { step in
            let angle = Double(step) / 12 * 2 * .pi
            return CameraPath.Point(lat: lat + 0.006 * sin(angle), lon: lon + 0.006 * cos(angle))
        }
    }

    /// Town A, a drive east of `driveSteps` × 0.02° of longitude, town B.
    private func townDriveTown(driveSteps: Int, stepDeg: Double) -> (route: [CameraPath.Point], stops: [CameraPath.Point]) {
        let townA = town(lat: 24.80, lon: 125.28)
        let start = townA[townA.count - 1]
        let drive = (1...driveSteps).map { CameraPath.Point(lat: start.lat, lon: start.lon + Double($0) * stepDeg) }
        let end = drive[drive.count - 1]
        let townB = town(lat: end.lat, lon: end.lon - 0.006)
        let stops = [townA[0], townA[4], townA[8], townA[12], townB[0], townB[6], townB[12]]
        return (townA + drive + townB, stops)
    }

    // MARK: - The ladder

    /// Two towns on one island and a home 400 km away: three levels, and each
    /// area's parent is the next place up that holds more than it does.
    func testTheLadderFindsTownIslandAndTheWholeTrip() throws {
        let config = try shipped()
        let points = [
            CameraPath.Point(lat: 24.800, lon: 125.280), CameraPath.Point(lat: 24.802, lon: 125.281),
            CameraPath.Point(lat: 24.801, lon: 125.284),
            CameraPath.Point(lat: 24.800, lon: 125.399), CameraPath.Point(lat: 24.803, lon: 125.400),
            CameraPath.Point(lat: 24.801, lon: 125.402),
            CameraPath.Point(lat: 25.080, lon: 121.230)
        ]
        let ladder = CameraPath.ContextLadder(points: points, config: config)
        XCTAssertEqual(ladder.levels.count, 3, "town → island → the whole trip")
        XCTAssertEqual(ladder.parent(of: [0, 1, 2]).count, 6, "a town's place is its island")
        XCTAssertEqual(ladder.parent(of: [2, 3]).count, 6, "a drive between the towns is on the island too")
        XCTAssertEqual(ladder.parent(of: [6]).count, 7, "home has no place of its own but the trip")
        XCTAssertEqual(ladder.parent(of: Set(points.indices)).count, 7, "nothing holds more than the whole trip")
    }

    /// Stops closer than the tightest frame never set a level: two photographs
    /// of one car park are one place, not a town inside a town.
    func testLinksShorterThanTheTightestFrameAreNotALevel() throws {
        let config = try shipped()
        let points = (0..<5).map { CameraPath.Point(lat: 24.80 + Double($0) * 0.001, lon: 125.28) }
        let ladder = CameraPath.ContextLadder(points: points, config: config)
        XCTAssertEqual(ladder.levels.count, 1)
    }

    // MARK: - The floor, in a film

    /// **The town is framed at its context floor**, not at town scale: the
    /// place it sits in (here the whole trip) ÷ `context_depth`. Still tighter
    /// than the drive, so the film keeps its three scales.
    func testATownIsFramedAtItsContextFloor() throws {
        let config = try shipped()
        let trip = townDriveTown(driveSteps: 20, stepDeg: 0.02)
        let line = try XCTUnwrap(CameraPath(route: trip.route, stops: trip.stops, config: config, totalDurationS: 60))
        XCTAssertEqual(line.areaSpansM.count, 3, "areas: \(line.areaSpansM.map { Int($0) })")
        guard line.areaSpansM.count == 3 else { return }
        let context = config.cameraContext
        let place = CameraPath.fittingSpanM(bounds: CameraPath.bounds(of: trip.stops), config: config)
        let floor = min(max(place / context.contextDepth, config.cameraSpanM), context.contextSpanMaxM)
        XCTAssertGreaterThan(floor, config.cameraSpanM * 2, "this trip must exercise the floor")
        XCTAssertEqual(line.areaSpansM[0], floor, accuracy: 1)
        XCTAssertEqual(line.areaSpansM[2], floor, accuracy: 1)
        XCTAssertLessThan(line.areaSpansM[0], line.areaSpansM[1], "the town is still tighter than the drive")
    }

    /// **A road trip's town stops at city scale.** The level above it is the
    /// whole 300 km route — a line, not a place — so the floor is the cap.
    func testTheFloorStopsAtCityScaleOnARoadTrip() throws {
        let config = try shipped()
        let trip = townDriveTown(driveSteps: 30, stepDeg: 0.1)
        let line = try XCTUnwrap(CameraPath(route: trip.route, stops: trip.stops, config: config, totalDurationS: 60))
        XCTAssertEqual(line.areaSpansM.count, 3, "areas: \(line.areaSpansM.map { Int($0) })")
        guard line.areaSpansM.count == 3 else { return }
        XCTAssertEqual(line.areaSpansM[0], config.cameraContext.contextSpanMaxM, accuracy: 1)
        XCTAssertEqual(line.areaSpansM[2], config.cameraContext.contextSpanMaxM, accuracy: 1)
    }

    /// Every derived copy carries the floor. A copy that dropped it would fall
    /// back to `.off` silently and put the 1.9 km town back.
    func testEveryCopyOfTheConfigKeepsTheContextFloor() throws {
        let config = try shipped()
        XCTAssertTrue(config.cameraContext.isEnabled)
        XCTAssertFalse(CameraContextConfig.off.isEnabled)
        let copies = [
            config.withFollowHeadingUp(true), config.withAllocationZeroShare(0.5),
            config.withRecapMode(config.recapMode), config.withTotalDuration(min: 60, max: 90),
            config.withCrossingBeatS(4), config.withKeyframeIntervalFrames(15),
            config.withSnapshotStations(maxMagnification: 1.1, padding: 1.03)
        ]
        for copy in copies {
            XCTAssertEqual(copy.cameraContext, config.cameraContext)
        }
    }
}
