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

    /// The shipped config with the context floor off (ADR 2026-09-24 (e)): the
    /// areas' own asks, which is what the area-splitting test pins. The floor on
    /// top of them is pinned in `CameraPathContextTests`.
    private func shippedWithoutContext() throws -> TrackingConfig.Export {
        let json = try String(contentsOf: Self.configURL, encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: #""context_depth":\s*[0-9.]+"#)
        let edited = pattern.stringByReplacingMatches(
            in: json, range: NSRange(json.startIndex..., in: json), withTemplate: #""context_depth": 0"#
        )
        XCTAssertNotEqual(edited, json, "the key moved — this helper no longer turns the floor off")
        return try TrackingConfigLoader.load(from: Data(edited.utf8)).export
    }

    /// A ~1.3 km loop of 12 steps around `centre`, closed.
    private func town(lat: Double, lon: Double) -> [CameraPath.Point] {
        (0...12).map { step in
            let angle = Double(step) / 12 * 2 * .pi
            return CameraPath.Point(lat: lat + 0.006 * sin(angle), lon: lon + 0.006 * cos(angle))
        }
    }

    /// Days in a town: its loop driven four times, each lap a street further
    /// north so a stop on a later lap is not found on the first. A zoom into a
    /// town is earned by driving in it (ADR file 2026-09-28), and one lap is not
    /// a day there.
    private func days(_ loop: [CameraPath.Point]) -> [CameraPath.Point] {
        (0..<4).flatMap { lap in loop.map { CameraPath.Point(lat: $0.lat + Double(lap) * 0.0005, lon: $0.lon) } }
    }

    /// Town A, a 40 km drive east, town B — the shape Chiu described: days in a
    /// town, one drive, days in another.
    private func townDriveTown() -> (route: [CameraPath.Point], stops: [CameraPath.Point]) {
        let townA = days(town(lat: 24.80, lon: 125.28))
        let start = townA[townA.count - 1]
        let drive = (1...20).map { CameraPath.Point(lat: start.lat, lon: start.lon + Double($0) * 0.02) }
        let end = drive[drive.count - 1]
        let townB = days(town(lat: end.lat, lon: end.lon - 0.006))
        let route = townA + drive + townB
        let stops = [townA[0], townA[4], townA[30], townA[51], townB[0], townB[26], townB[51]]
        return (route, stops)
    }

    private func path(_ config: TrackingConfig.Export) throws -> CameraPath {
        let trip = townDriveTown()
        return try XCTUnwrap(CameraPath(route: trip.route, stops: trip.stops, config: config, totalDurationS: 60))
    }

    /// The towns get town-sized frames, the drive a wide one — the thing Chiu
    /// asked for — and the tight areas really are tighter than the one span the
    /// old rule gave the whole trip.
    ///
    /// Run with the context floor off: the floor deliberately widens the towns
    /// past `oneSpan / 4` (Chiu, ADR 2026-09-24 (e)), and what this pins is the
    /// split itself. `CameraPathContextTests` pins the same trip with it on.
    func testATownDriveTownTripIsFramedAtThreeScales() throws {
        let config = try shippedWithoutContext()
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

    /// **A long drive is never framed at a town's scale** (Chiu 2026-09-28, the
    /// New Zealand film). Framed at its own scale a 180 km drive crosses its
    /// window in a few seconds — under the two-beat minimum — and the brief-area
    /// merge used to hand it to the town beside it, band and all: the drive was
    /// then shown at town scale and, paced by screen distance, took several
    /// times as long. A brief area is now never absorbed into a neighbour more
    /// than `target_zoom_ratio` tighter than itself.
    func testALongDriveKeepsItsOwnWideFrame() throws {
        let config = try shippedWithoutContext()
        // The New Zealand shape: two towns where the film stops long (photo
        // decks) and drives little, a long drive between them, and later days
        // driven around a third town that take most of the travel clock — so
        // the drive's own frame crosses in a couple of seconds, under the
        // two-beat minimum the old rule measured.
        let townA = town(lat: 24.80, lon: 125.28)
        let start = townA[townA.count - 1]
        let drive = (1...60).map { CameraPath.Point(lat: start.lat, lon: start.lon + Double($0) * 0.03) }
        let end = drive[drive.count - 1]
        let townB = town(lat: end.lat, lon: end.lon - 0.006)
        let townC = days(days(town(lat: end.lat + 0.03, lon: end.lon)))
        let route = townA + drive + townB + townC
        let stops = [townA[0], townA[4], townA[8], townA[12], townB[0], townB[6], townB[12],
                     townC[60], townC[120], townC[180], townC[townC.count - 1]]
        let line = try XCTUnwrap(CameraPath(
            route: route, stops: stops, config: config, stopHoldsS: Array(repeating: 3, count: stops.count),
            totalDurationS: 60
        ))

        let driveM = Geo.distanceM(latA: start.lat, lonA: start.lon, latB: end.lat, lonB: end.lon)
        XCTAssertGreaterThan(
            try XCTUnwrap(line.areaSpansM.max()), driveM / 4,
            "the \(Int(driveM / 1000)) km drive is framed at \(line.areaSpansM.map { Int($0) }) m"
        )
        // And the frame the drive is actually shown in, halfway along it.
        let longest = try XCTUnwrap(line.timeline.max { lhs, rhs in
            func metres(_ entry: CameraPath.TimelineEntry) -> Double {
                if case let .travel(fromM, toM) = entry.phase { return toM - fromM }
                return 0
            }
            return metres(lhs) < metres(rhs)
        })
        let midDrive = line.cameraFrame(atTime: (longest.startS + longest.endS) / 2).spanM
        XCTAssertGreaterThan(midDrive, driveM / 4, "the drive plays at \(Int(midDrive)) m")
    }

    /// **A road trip is framed at one scale set by its own towns, and a place
    /// only passed through is not zoomed into** (Chiu 2026-09-29, the New Zealand
    /// film: an airport and a mall in one city, then a lake where the geocoder
    /// names one of three stops a "Ward" — 「基本上沒有市區行程，拉近又拉遠很浪費時間」,
    /// 「看不出來你在哪裡」). The frame holds the two nearest other towns, so every
    /// town is seen with its neighbours, and nothing zooms in or out.
    func testARoadTripIsFramedByItsOwnTownsWithoutZooming() throws {
        let config = try shipped()
        func leg(from start: CameraPath.Point, steps: Int, dLat: Double, dLon: Double) -> [CameraPath.Point] {
            (1...steps).map { CameraPath.Point(lat: start.lat + Double($0) * dLat, lon: start.lon + Double($0) * dLon) }
        }
        let airport = CameraPath.Point(lat: -43.49, lon: 172.53)
        let mall = leg(from: airport, steps: 8, dLat: 0, dLon: -0.011)
        let toLake = leg(from: mall[mall.count - 1], steps: 60, dLat: -0.012, dLon: -0.025)
        let shore = leg(from: toLake[toLake.count - 1], steps: 10, dLat: 0, dLon: -0.002)
        let toTwizel = leg(from: shore[shore.count - 1], steps: 20, dLat: -0.02, dLon: -0.005)
        let toWanaka = leg(from: toTwizel[toTwizel.count - 1], steps: 30, dLat: -0.012, dLon: -0.025)
        let route = [airport] + mall + toLake + shore + toTwizel + toWanaka
        let lake = toLake[toLake.count - 1], twizel = toTwizel[toTwizel.count - 1]
        let stops = [airport, mall[mall.count - 1], lake, lake, shore[shore.count - 1], twizel, toWanaka[toWanaka.count - 1]]
        let towns = ["Christchurch", "Christchurch", "Lake Tekapo", "Lake Tekapo", "Pukaki Ward", "Twizel", "Wānaka"]
        let line = try XCTUnwrap(CameraPath(
            route: route, stops: stops, config: config, totalDurationS: 60, stopPlaces: towns
        ))
        XCTAssertTrue(line.reframeArcs.isEmpty, "zoomed in and out at \(line.areaSpansM.map { Int($0) }) m")
        let lakeToTwizel = Geo.distanceM(latA: lake.lat, lonA: lake.lon, latB: twizel.lat, lonB: twizel.lon)
        XCTAssertGreaterThan(try XCTUnwrap(line.areaSpansM.min()), lakeToTwizel,
                             "the lake is framed without its neighbouring towns")
    }

    /// **A trip that is all one town is framed exactly as before** (Chiu
    /// 2026-09-29: 宮古島市區日會比以前寬 這也不合理). Miyakojima geocodes every
    /// stop to one municipality: there is no next town to show, so the towns
    /// change nothing — every frame is the one the trip gets with no names at all.
    func testATripOfOneTownIsFramedAsWithoutTowns() throws {
        let config = try shipped()
        let trip = townDriveTown()
        let named = try XCTUnwrap(CameraPath(
            route: trip.route, stops: trip.stops, config: config, totalDurationS: 60,
            stopPlaces: trip.stops.map { _ in "Miyakojima" }
        ))
        let unnamed = try XCTUnwrap(CameraPath(route: trip.route, stops: trip.stops, config: config, totalDurationS: 60))
        XCTAssertEqual(named.areaSpansM, unnamed.areaSpansM)
        for frame in stride(from: 0, to: named.frameCount, by: 11) {
            let time = Double(frame) / Double(config.fps)
            XCTAssertEqual(named.cameraFrame(atTime: time), unnamed.cameraFrame(atTime: time), "t=\(time)")
        }
    }

    /// **Days driven around a town still earn their zoom** on a road trip: a town
    /// that fits inside the journey's frame and is driven around for longer than
    /// the zoom costs keeps its own, tighter framing (「除非是使用者有市區行程」).
    func testATownDrivenAroundKeepsItsZoomOnARoadTrip() throws {
        let config = try shipped()
        let trip = townDriveTown()
        let towns = ["A", "A", "A", "A", "B", "B", "B"]
        let far = CameraPath.Point(lat: trip.route[trip.route.count - 1].lat - 0.5, lon: trip.route[trip.route.count - 1].lon)
        let line = try XCTUnwrap(CameraPath(
            route: trip.route + [far], stops: trip.stops + [far], config: config, totalDurationS: 60,
            stopPlaces: towns + ["C"]
        ))
        let widest = try XCTUnwrap(line.areaSpansM.max())
        XCTAssertLessThan(try XCTUnwrap(line.areaSpansM.first), widest, "the town days lost their zoom: \(line.areaSpansM)")
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
