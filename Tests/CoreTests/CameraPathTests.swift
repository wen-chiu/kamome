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
        maxHoldFraction: Double = 0.5
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
            keyframeIntervalFrames: 15
        )
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
