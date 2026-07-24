import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// §4.5 step 1: speed-warped camera path. Synthetic routes pin down the
/// timing contract; the perth fixture proves the path survives a real
/// engine-produced trip.
final class CameraPathTests: XCTestCase {
    /// 1 km straight line, 11 evenly spaced vertices along a meridian.
    private let straightRoute: [CameraPath.Point] = (0...10).map {
        CameraPath.Point(lat: -32.0 + Double($0) * 0.0009, lon: 115.75)
    }

    private func exportConfig(
        targetDurationS: Double = 30,
        fps: Int = 30,
        stopHoldS: Double = 1.5,
        maxHoldFraction: Double = 0.5,
        followHeadingUp: Bool = false
    ) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS,
            fps: fps,
            stopHoldS: stopHoldS,
            maxHoldFraction: maxHoldFraction,
            gifFps: 12,
            gifWidthPx: 480,
            frameWidthPx: 1080,
            frameHeightPx: 1920,
            cameraSpanM: 1500,
            wideSpanPadding: 1.15,
            zoomTransitionS: 0.8,
            followHeadingUp: followHeadingUp,
            keyframeIntervalFrames: 15,
            titleCardS: 2.5,
            endCardS: 3,
            videoBitrateMbps: 5
        )
    }

    /// A route large enough that the whole-trip fitting span exceeds the close
    /// follow span, so the wide↔close difference is observable.
    private let longRoute: [CameraPath.Point] = (0...10).map {
        CameraPath.Point(lat: -32.0 + Double($0) * 0.1, lon: 115.75)
    }

    func testVideoDurationIsTargetRegardlessOfRouteLength() throws {
        let short = try XCTUnwrap(CameraPath(route: straightRoute, stops: [], config: exportConfig()))
        let longRoute = (0...10).map { CameraPath.Point(lat: -32.0 + Double($0) * 0.9, lon: 115.75) }
        let long = try XCTUnwrap(CameraPath(route: longRoute, stops: [], config: exportConfig()))

        XCTAssertEqual(short.frameCount, 900)  // 30 s × 30 fps
        XCTAssertEqual(long.frameCount, 900)
        XCTAssertEqual(short.durationS, 30)
        XCTAssertEqual(long.durationS, 30)
    }

    func testStartsAtRouteStartAndEndsAtRouteEnd() throws {
        let path = try XCTUnwrap(CameraPath(route: straightRoute, stops: [], config: exportConfig()))

        let first = path.position(atTime: 0)
        XCTAssertEqual(first.lat, straightRoute[0].lat, accuracy: 1e-9)
        XCTAssertEqual(first.lon, straightRoute[0].lon, accuracy: 1e-9)

        let last = path.position(atTime: 30)
        XCTAssertEqual(last.lat, straightRoute.last!.lat, accuracy: 1e-9)
        XCTAssertEqual(last.lon, straightRoute.last!.lon, accuracy: 1e-9)
    }

    func testProgressIsMonotonicOverFrames() throws {
        let midStop = CameraPath.Point(lat: straightRoute[5].lat, lon: straightRoute[5].lon)
        let path = try XCTUnwrap(CameraPath(route: straightRoute, stops: [midStop], config: exportConfig()))

        var previousLat = -Double.greatestFiniteMagnitude
        for frame in 0..<path.frameCount {
            let position = path.position(atFrame: frame)
            XCTAssertGreaterThanOrEqual(position.lat + 1e-12, previousLat, "camera moved backwards at frame \(frame)")
            previousLat = position.lat
        }
    }

    func testHoldPinsCameraToStopForConfiguredDuration() throws {
        let midStop = CameraPath.Point(lat: straightRoute[5].lat, lon: straightRoute[5].lon)
        let path = try XCTUnwrap(CameraPath(route: straightRoute, stops: [midStop], config: exportConfig()))

        let holdFrames = (0..<path.frameCount).filter { path.position(atFrame: $0).holdingStopIndex == 0 }
        // 1.5 s hold at 30 fps ≈ 45 frames (±1 for frame-boundary rounding).
        XCTAssertEqual(Double(holdFrames.count), 45, accuracy: 1)
        for frame in holdFrames {
            let position = path.position(atFrame: frame)
            XCTAssertEqual(position.lat, midStop.lat, accuracy: 1e-9)
            XCTAssertEqual(position.lon, midStop.lon, accuracy: 1e-9)
        }
    }

    func testEasingSlowsCameraNearStops() throws {
        let midStop = CameraPath.Point(lat: straightRoute[5].lat, lon: straightRoute[5].lon)
        let path = try XCTUnwrap(CameraPath(route: straightRoute, stops: [midStop], config: exportConfig()))

        func speed(atFrame frame: Int) -> Double {
            abs(path.position(atFrame: frame + 1).lat - path.position(atFrame: frame).lat)
        }
        // First leg runs from t=0 to the hold; compare its edges to its middle.
        let firstHoldFrame = try XCTUnwrap(
            (0..<path.frameCount).first { path.position(atFrame: $0).holdingStopIndex != nil }
        )
        let midLegFrame = firstHoldFrame / 2
        XCTAssertGreaterThan(speed(atFrame: midLegFrame), speed(atFrame: 0) * 2, "mid-leg should be much faster than launch")
        let brakingSpeed = speed(atFrame: firstHoldFrame - 2)
        XCTAssertGreaterThan(speed(atFrame: midLegFrame), brakingSpeed * 2, "camera should brake into the hold")
    }

    func testStopDenseTripShrinksHoldsToPreserveTravelTime() throws {
        // 30 stops × 1.5 s = 45 s of holds against a 30 s video: holds must
        // shrink to max_hold_fraction (15 s total), leaving 15 s of travel.
        let stops = (1...30).map { _ in straightRoute[5] }
        let path = try XCTUnwrap(CameraPath(route: straightRoute, stops: stops, config: exportConfig()))

        let holdFrames = (0..<path.frameCount).filter { path.position(atFrame: $0).holdingStopIndex != nil }
        XCTAssertEqual(Double(holdFrames.count), 450, accuracy: Double(stops.count))
    }

    // MARK: - Follow-cam framing (prototype §2.3)

    func testCameraWidensForTitleAndEndClosesForBody() throws {
        let config = exportConfig()
        let path = try XCTUnwrap(CameraPath(route: longRoute, stops: [], config: config))

        let opening = path.cameraFrame(atTime: 0)
        let body = path.cameraFrame(atTime: config.targetDurationS / 2)
        let closing = path.cameraFrame(atTime: config.targetDurationS)

        // Body is the tight follow span; the establishing/closing shots are much wider.
        XCTAssertEqual(body.spanM, config.cameraSpanM, accuracy: 1e-6, "body sits at the close follow span")
        XCTAssertGreaterThan(opening.spanM, config.cameraSpanM * 10, "title shot frames the whole trip")
        XCTAssertGreaterThan(closing.spanM, config.cameraSpanM * 10, "end shot frames the whole trip")

        // Wide shots center on the trip; the body follows the vehicle.
        let tripCenterLat = (longRoute.first!.lat + longRoute.last!.lat) / 2
        XCTAssertEqual(opening.centerLat, tripCenterLat, accuracy: 1e-6, "wide shot centers the trip")
        let vehicle = path.position(atTime: config.targetDurationS / 2)
        XCTAssertEqual(body.centerLat, vehicle.lat, accuracy: 1e-6, "close shot rides the vehicle")
    }

    func testTinyTripNeverZoomsOutPastCloseSpan() throws {
        // straightRoute is ~1 km — its fitting span is under the close span, so
        // the wide floor collapses to the close span and there is no zoom-out.
        let config = exportConfig()
        let path = try XCTUnwrap(CameraPath(route: straightRoute, stops: [], config: config))
        XCTAssertEqual(path.cameraFrame(atTime: 0).spanM, config.cameraSpanM, accuracy: 1e-6)
        XCTAssertEqual(path.cameraFrame(atTime: 15).spanM, config.cameraSpanM, accuracy: 1e-6)
    }

    func testZoomOnlyTightensFromWideIntoBody() throws {
        let config = exportConfig()
        let path = try XCTUnwrap(CameraPath(route: longRoute, stops: [], config: config))
        var previous = Double.greatestFiniteMagnitude
        for time in stride(from: 0.0, through: config.titleCardS + config.zoomTransitionS + 1, by: 0.1) {
            let span = path.cameraFrame(atTime: time).spanM
            XCTAssertLessThanOrEqual(span, previous + 1e-6, "span should only tighten into the body at t=\(time)")
            previous = span
        }
    }

    func testHeadingFollowsRouteDirection() throws {
        let north = try XCTUnwrap(CameraPath(route: straightRoute, stops: [], config: exportConfig()))
        XCTAssertEqual(north.position(atTime: 15).heading, 0, accuracy: 1, "north-bound → heading 0°")

        let eastRoute = (0...10).map { CameraPath.Point(lat: -32.0, lon: 115.75 + Double($0) * 0.0009) }
        let east = try XCTUnwrap(CameraPath(route: eastRoute, stops: [], config: exportConfig()))
        XCTAssertEqual(east.position(atTime: 15).heading, 90, accuracy: 1, "east-bound → heading 90°")
    }

    func testBearingStaysZeroUnlessHeadingUpEnabled() throws {
        let eastRoute = (0...10).map { CameraPath.Point(lat: -32.0, lon: 115.75 + Double($0) * 0.0009) }
        // Default: north-up map, the marker rotates — bearing stays 0.
        let northUp = try XCTUnwrap(CameraPath(route: eastRoute, stops: [], config: exportConfig()))
        XCTAssertEqual(northUp.cameraFrame(atTime: 15).bearing, 0, accuracy: 1e-9)
        // follow_heading_up on: the body rotates to the travel heading.
        let rotated = try XCTUnwrap(
            CameraPath(route: eastRoute, stops: [], config: exportConfig(followHeadingUp: true))
        )
        XCTAssertEqual(rotated.cameraFrame(atTime: 15).bearing, 90, accuracy: 1, "heading-up rotates the map east→up")
    }

    func testDegenerateRoutesProduceNoPath() {
        XCTAssertNil(CameraPath(route: [], stops: [], config: exportConfig()))
        XCTAssertNil(CameraPath(route: [straightRoute[0]], stops: [], config: exportConfig()))
        // Two identical points: zero-length route.
        XCTAssertNil(CameraPath(route: [straightRoute[0], straightRoute[0]], stops: [], config: exportConfig()))
    }

    func testPerthReplayTripProducesFullCoveragePath() throws {
        let engine = try GPXReplay.run(fixture: "perth_margaret_river_day1.gpx")
        let route = engine.segments.flatMap(\.points).map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
        let stops = engine.stops.map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
        let config = try GPXReplay.loadConfig().export
        let path = try XCTUnwrap(CameraPath(route: route, stops: stops, config: config))

        XCTAssertEqual(path.frameCount, Int(config.targetDurationS) * config.fps)
        let first = path.position(atTime: 0)
        XCTAssertEqual(first.lat, route.first!.lat, accuracy: 1e-9)
        let last = path.position(atTime: config.targetDurationS)
        XCTAssertEqual(last.lat, route.last!.lat, accuracy: 1e-9)

        // Every stop gets its hold moment.
        let heldStops = Set((0..<path.frameCount).compactMap { path.position(atFrame: $0).holdingStopIndex })
        XCTAssertEqual(heldStops.count, stops.count)
    }
}
