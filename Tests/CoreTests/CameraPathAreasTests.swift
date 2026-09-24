import KamomeConfig
@testable import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// **The body is framed area by area** (ADR 2026-09-24, `CameraPathAreas`).
///
/// Chiu, on his Vietnam and Miyakojima films: after landing the route could not
/// be read, because one span sized by the whole destination framed every town
/// loop. These pin the rule that replaced it, on the **shipped** tunables — a
/// hand-built config leaves areas off (`camera_area_split_ratio` defaults to
/// infinity), which is the one-area film the older tests in this directory pin.
final class CameraPathAreasTests: XCTestCase {
    private static let configURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Config/TrackingConfig.json")

    private func shipped() throws -> TrackingConfig.Export {
        try TrackingConfigLoader.load(contentsOf: Self.configURL).export
    }

    /// The shipped config with areas off: a split ratio no two stretches can
    /// exceed, so every trip is one area — the film before ADR 2026-09-24.
    private func shippedWithoutAreas() throws -> TrackingConfig.Export {
        let json = try String(contentsOf: Self.configURL, encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #""camera_area_split_ratio":\s*[0-9.]+"#)
        let edited = pattern.stringByReplacingMatches(
            in: json, range: NSRange(json.startIndex..., in: json),
            withTemplate: #""camera_area_split_ratio": 1e300"#
        )
        XCTAssertNotEqual(edited, json, "the key moved — this helper no longer turns areas off")
        return try TrackingConfigLoader.load(from: Data(edited.utf8)).export
    }

    /// A ~1.3 km loop of 12 steps around `centre`, closed.
    private func town(lat: Double, lon: Double) -> [CameraPath.Point] {
        (0...12).map { step in
            let angle = Double(step) / 12 * 2 * .pi
            return CameraPath.Point(lat: lat + 0.006 * sin(angle), lon: lon + 0.006 * cos(angle))
        }
    }

    /// Town A, a 40 km drive east, town B — the shape Chiu described: days in a
    /// town, one drive, days in another.
    private func townDriveTown() -> (route: [CameraPath.Point], stops: [CameraPath.Point]) {
        let townA = town(lat: 24.80, lon: 125.28)
        let start = townA[townA.count - 1]
        let drive = (1...20).map { CameraPath.Point(lat: start.lat, lon: start.lon + Double($0) * 0.02) }
        let end = drive[drive.count - 1]
        let townB = town(lat: end.lat, lon: end.lon - 0.006).map {
            CameraPath.Point(lat: $0.lat, lon: $0.lon)
        }
        let route = townA + drive + townB
        let stops = [townA[0], townA[4], townA[8], townA[12], townB[0], townB[6], townB[12]]
        return (route, stops)
    }

    private func path(_ config: TrackingConfig.Export) throws -> CameraPath {
        let trip = townDriveTown()
        return try XCTUnwrap(CameraPath(route: trip.route, stops: trip.stops, config: config, totalDurationS: 60))
    }

    /// The towns get town-sized frames, the drive a wide one — the thing Chiu
    /// asked for — and the tight areas really are tighter than the one span the
    /// old rule gave the whole trip.
    func testATownDriveTownTripIsFramedAtThreeScales() throws {
        let config = try shipped()
        let line = try path(config)
        XCTAssertEqual(line.areaSpansM.count, 3, "areas: \(line.areaSpansM.map { Int($0) })")
        guard line.areaSpansM.count == 3 else { return }
        let (first, drive, last) = (line.areaSpansM[0], line.areaSpansM[1], line.areaSpansM[2])
        XCTAssertGreaterThan(drive, first * config.cameraAreaSplitRatio)
        XCTAssertGreaterThan(drive, last * config.cameraAreaSplitRatio)
        let bounds = CameraPath.bounds(of: townDriveTown().route)
        let oneSpan = CameraPath.fittingSpanM(bounds: bounds, config: config)
            * config.wideSpanPadding / config.targetZoomRatio
        XCTAssertLessThan(first, oneSpan / 4, "a town must not be framed at the trip's one span")
        XCTAssertEqual(line.reframeArcs.count, 2, "one change of scale at each end of the drive")
    }

    /// **The span changes only inside a reframe beat** — never while the vehicle
    /// travels, never during a stop's scene. That is the line between this and
    /// the 2026-08-02 act camera, which re-framed mid-motion.
    func testTheSpanChangesOnlyWhileTheVehicleWaitsInAReframeBeat() throws {
        let config = try shipped()
        let line = try path(config)
        let beats = line.reframeArcs.map { $0.startS...$0.endS }
        XCTAssertFalse(beats.isEmpty)
        let step = 1.0 / Double(config.fps)
        func inABeat(_ time: Double) -> Bool { beats.contains { $0.contains(time) } }
        var time = line.openingS + step
        while time < line.durationS - config.endCardS - config.endRevealS {
            if !inABeat(time), !inABeat(time - step) {
                XCTAssertEqual(
                    line.cameraFrame(atTime: time).spanM, line.cameraFrame(atTime: time - step).spanM,
                    accuracy: 1e-6, "the span moved at t=\(time) outside every reframe beat"
                )
            }
            time += step
        }
        // Inside a beat the vehicle is parked where the beat began, and no stop's
        // scene is playing: a stop is a still beat and never zooms.
        for beat in beats {
            let parked = line.position(atTime: beat.lowerBound)
            for time in stride(from: beat.lowerBound, to: beat.upperBound, by: step) {
                let now = line.position(atTime: time)
                XCTAssertNil(now.holdingStopIndex, "a stop's scene plays inside the zoom at t=\(time)")
                XCTAssertEqual(now.lat, parked.lat, accuracy: 1e-12, "the vehicle moved during a zoom at t=\(time)")
                XCTAssertEqual(now.lon, parked.lon, accuracy: 1e-12, "the vehicle moved during a zoom at t=\(time)")
            }
        }
    }

    /// **A stop is presented at the tighter of its two framings**: the drive's
    /// last stop (the first of town B) after zooming in, the first town's last
    /// stop before zooming out.
    func testEachBoundaryStopIsShownAtItsTighterFraming() throws {
        let config = try shipped()
        let line = try path(config)
        guard line.areaSpansM.count == 3 else { return XCTFail("expected three areas") }
        for hold in line.holds {
            let middle = (hold.startS + hold.endS) / 2
            let span = line.cameraFrame(atTime: middle).spanM
            XCTAssertLessThan(
                span, line.areaSpansM[1],
                "stop \(hold.stopIndex) is presented at the drive's scale — every stop here is in a town"
            )
        }
    }

    /// Every frame still shares its ground with the one before it, through both
    /// zooms: the move is a contained zoom about a stationary subject.
    func testZoomingBetweenAreasNeverBreaksContinuity() throws {
        let config = try shipped()
        let line = try path(config)
        let step = 1.0 / Double(config.fps)
        var previous = line.cameraFrame(atTime: 0)
        for frame in 1..<line.frameCount {
            let now = line.cameraFrame(atTime: Double(frame) * step)
            let moved = Geo.distanceM(
                latA: previous.centerLat, lonA: previous.centerLon, latB: now.centerLat, lonB: now.centerLon
            )
            // Contained: the tighter frame's centre may move at most half the
            // difference in spans (`containedLerp`), plus a dolly's ordinary step.
            let allowance = abs(now.spanM - previous.spanM) / 2 + min(now.spanM, previous.spanM) * 0.05
            XCTAssertLessThanOrEqual(moved, allowance, "frame \(frame) jumped \(Int(moved)) m")
            previous = now
        }
    }

    /// **A one-area film is the film it always was**: with areas enabled on a
    /// trip that only ever asks for one scale, every frame is bit-identical to
    /// the same trip with areas off.
    func testAOneAreaTripIsUnchangedByAreas() throws {
        let config = try shipped()
        let route = (0...20).map { CameraPath.Point(lat: 24.80 + Double($0) * 0.01, lon: 125.28) }
        let stops = [route[0], route[10], route[20]]
        let withAreas = try XCTUnwrap(CameraPath(route: route, stops: stops, config: config, totalDurationS: 40))
        let without = try XCTUnwrap(CameraPath(
            route: route, stops: stops, config: try shippedWithoutAreas(), totalDurationS: 40
        ))
        XCTAssertEqual(withAreas.areaSpansM.count, 1)
        for frame in stride(from: 0, to: withAreas.frameCount, by: 7) {
            let time = Double(frame) / Double(config.fps)
            XCTAssertEqual(withAreas.cameraFrame(atTime: time), without.cameraFrame(atTime: time), "t=\(time)")
        }
    }

    /// The dolly's travel is the camera's path, not the subject's: a loop that
    /// fits inside the frame costs nothing, a straight drive nearly its length.
    func testTheDollyTravelsOnlyWhereTheSubjectLeavesTheFrame() throws {
        let config = try shipped()
        let loop = town(lat: 24.80, lon: 125.28)
        let inside = FollowCamera.travelM(
            route: loop, routeBounds: CameraPath.bounds(of: loop), spanM: 5000, config: config
        )
        XCTAssertEqual(inside, 0, accuracy: 1e-6)
        let drive = (0...20).map { CameraPath.Point(lat: 24.80, lon: 125.28 + Double($0) * 0.02) }
        let lengthM = Geo.distanceM(latA: 24.80, lonA: 125.28, latB: 24.80, lonB: 125.68)
        let travelled = FollowCamera.travelM(
            route: drive, routeBounds: CameraPath.bounds(of: drive), spanM: 5000, config: config
        )
        // Clamped to the route at both ends, then dragged to the safe-zone edge by
        // the subject standing at each end: the drive less 0.8 of a window.
        XCTAssertEqual(travelled, lengthM - 5000 * config.cameraSafeZoneFraction, accuracy: lengthM * 0.01)
    }

    /// **The world clamp never teleports the camera** (regression, ADR
    /// 2026-09-24). A route barely narrower than the window made the clamp
    /// snap the frame 1.6 km in one step whenever the subject came back into the
    /// dead zone after `confine` had dragged it out.
    func testTheWorldClampNeverSnapsTheFrame() throws {
        let config = try shipped()
        // A 3 km out-and-back north-south in a portrait frame 1.9 km wide and
        // 3.4 km tall: the clamp range collapses to the middle, and the subject
        // still leaves the dead zone at both ends.
        let route = (0...30).map { step -> CameraPath.Point in
            let phase = Double(step) / 30
            return CameraPath.Point(lat: 24.80 + 0.027 * sin(phase * .pi), lon: 125.28 + 0.004 * phase)
        }
        let subject = (0..<600).map { frame -> CameraPath.Point in
            let index = Double(frame) / 600 * 30
            let low = Int(index), high = min(low + 1, 30), fraction = index - Double(low)
            return CameraPath.Point(
                lat: route[low].lat + (route[high].lat - route[low].lat) * fraction,
                lon: route[low].lon + (route[high].lon - route[low].lon) * fraction
            )
        }
        let track = FollowCamera.track(
            subject: subject, parked: Array(repeating: false, count: subject.count),
            routeBounds: CameraPath.bounds(of: route), spanM: 1900, config: config
        )
        for (before, now) in zip(track, track.dropFirst()) {
            let moved = Geo.distanceM(
                latA: before.centerLat, lonA: before.centerLon, latB: now.centerLat, lonB: now.centerLon
            )
            XCTAssertLessThan(moved, 1900 * 0.1, "the frame jumped \(Int(moved)) m in one step")
        }
    }
}
