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
            actSplitKm: 25,
            followHeadingUp: followHeadingUp,
            deckPhotoHoldS: 0.8,
            deckZoomS: 0.5,
            deckLabelLeadS: 0.6, subjectParkS: 0.4,
            openingCountryS: 3.0, openingRegionalS: 3.5, openingRouteS: 0.4,
            countryViewPadding: 2.2, firstStopDwellScale: 0.55,
            stopDwellMinS: 6, stopDwellMaxS: 25,
            totalDurationMinS: 60, totalDurationMaxS: 90,
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

    /// `holds` exposes one window per stop in playback order even when stops are
    /// passed out of route order — the timeline anchors each stop scene to them.
    func testHoldsExposeOneWindowPerStopInPlaybackOrder() throws {
        // route[7] is passed first but lies later along the meridian than route[3].
        let path = try XCTUnwrap(
            CameraPath(route: straightRoute, stops: [straightRoute[7], straightRoute[3]], config: exportConfig())
        )
        let holds = path.holds

        XCTAssertEqual(holds.count, 2)
        XCTAssertEqual(holds.map(\.stopIndex), [1, 0], "the second stop passed lies earlier on the route")
        XCTAssertLessThan(holds[0].startS, holds[1].startS)
        for hold in holds {
            XCTAssertEqual(hold.endS - hold.startS, 1.5, accuracy: 1e-9)
            // The camera is actually holding this stop throughout the window.
            let mid = path.position(atTime: (hold.startS + hold.endS) / 2)
            XCTAssertEqual(mid.holdingStopIndex, hold.stopIndex)
        }
    }

    func testPerStopHoldsScaleWithSuppliedDurations() throws {
        // Two stops with explicit per-stop holds (photo-deck dwell, §5): the
        // first should hold ~3× as many frames as the second.
        let stops = [straightRoute[3], straightRoute[7]]
        let path = try XCTUnwrap(
            CameraPath(route: straightRoute, stops: stops, config: exportConfig(), stopHoldsS: [3.0, 1.0])
        )
        let firstFrames = (0..<path.frameCount).filter { path.position(atFrame: $0).holdingStopIndex == 0 }.count
        let secondFrames = (0..<path.frameCount).filter { path.position(atFrame: $0).holdingStopIndex == 1 }.count
        // 3 s and 1 s at 30 fps ≈ 90 and 30 frames.
        XCTAssertEqual(Double(firstFrames), 90, accuracy: 2)
        XCTAssertEqual(Double(secondFrames), 30, accuracy: 2)
    }

    func testPerStopHoldsAreCappedTogetherKeepingProportions() throws {
        // 6 s + 6 s = 12 s of holds against a 30 s video caps at 15 s
        // (max_hold_fraction 0.5); each scales to 7.5 s but stays equal.
        let stops = [straightRoute[3], straightRoute[7]]
        let path = try XCTUnwrap(
            CameraPath(route: straightRoute, stops: stops, config: exportConfig(), stopHoldsS: [12.0, 12.0])
        )
        let firstFrames = (0..<path.frameCount).filter { path.position(atFrame: $0).holdingStopIndex == 0 }.count
        let secondFrames = (0..<path.frameCount).filter { path.position(atFrame: $0).holdingStopIndex == 1 }.count
        XCTAssertEqual(Double(firstFrames + secondFrames), 450, accuracy: 3, "total holds capped at 15 s")
        XCTAssertEqual(firstFrames, secondFrames, accuracy: 2, "equal holds stay equal after the cap")
    }

    func testStopDenseTripShrinksHoldsToPreserveTravelTime() throws {
        // 30 stops × 1.5 s = 45 s of holds against a 30 s video: holds must
        // shrink to max_hold_fraction (15 s total), leaving 15 s of travel.
        let stops = (1...30).map { _ in straightRoute[5] }
        let path = try XCTUnwrap(CameraPath(route: straightRoute, stops: stops, config: exportConfig()))

        let holdFrames = (0..<path.frameCount).filter { path.position(atFrame: $0).holdingStopIndex != nil }
        XCTAssertEqual(Double(holdFrames.count), 450, accuracy: Double(stops.count))
    }

    // MARK: - Fixed-frame framing (Chiu 2026-07-25)

    /// The camera holds **one** frame for a continuous trip: no establishing
    /// zoom, no follow-cam, no stop dolly. A still map is what makes the distance
    /// covered legible, and it keeps GPS wobble at its true scale.
    func testContinuousTripHoldsASingleFixedFrame() throws {
        let config = exportConfig()
        let path = try XCTUnwrap(CameraPath(route: longRoute, stops: [longRoute[5]], config: config))

        let samples = stride(from: 0.0, through: config.targetDurationS, by: 0.25)
            .map { path.cameraFrame(atTime: $0) }
        let first = try XCTUnwrap(samples.first)
        for frame in samples {
            XCTAssertEqual(frame.spanM, first.spanM, accuracy: 1e-6, "the span must never change")
            XCTAssertEqual(frame.centerLat, first.centerLat, accuracy: 1e-9, "the centre must never move")
            XCTAssertEqual(frame.centerLon, first.centerLon, accuracy: 1e-9, "the centre must never move")
        }
        // And that one frame holds the whole route. `spanM` is the *horizontal*
        // span; this route runs north-south, so compare against what the portrait
        // frame covers vertically.
        let extentM = Geo.distanceM(
            latA: longRoute.first!.lat, lonA: longRoute.first!.lon,
            latB: longRoute.last!.lat, lonB: longRoute.last!.lon
        )
        let verticalCoverM = first.spanM * Double(config.frameHeightPx) / Double(config.frameWidthPx)
        XCTAssertGreaterThan(verticalCoverM, extentM, "the held frame must contain the whole route")
    }

    /// A genuine jump — a flight, a ferry, a drive resuming in another region —
    /// is the one thing that re-frames the camera, and it eases rather than cuts.
    func testLargeJumpSplitsIntoTwoFramesAndEasesBetweenThem() throws {
        let config = exportConfig()
        // Two clusters ~200 km apart: far beyond act_split_km.
        let near = (0...10).map { CameraPath.Point(lat: -32.0 + Double($0) * 0.001, lon: 115.75) }
        let far = (0...10).map { CameraPath.Point(lat: -30.2 + Double($0) * 0.001, lon: 115.75) }
        let path = try XCTUnwrap(CameraPath(route: near + far, stops: [], config: config))

        let opening = path.cameraFrame(atTime: 0.5)
        let closing = path.cameraFrame(atTime: config.targetDurationS - 0.5)
        XCTAssertGreaterThan(
            abs(opening.centerLat - closing.centerLat), 1.0, "each act frames its own cluster"
        )
        // Neither act is framed to the whole ~200 km — that is what splitting buys.
        XCTAssertLessThan(opening.spanM, 100_000, "the first act frames only its own cluster")

        // The seam eases: some sample sits strictly between the two centres.
        let centres = stride(from: 0.0, through: config.targetDurationS, by: 0.1)
            .map { path.cameraFrame(atTime: $0).centerLat }
        let low = min(opening.centerLat, closing.centerLat), high = max(opening.centerLat, closing.centerLat)
        XCTAssertTrue(
            centres.contains { $0 > low + 0.05 && $0 < high - 0.05 },
            "the camera must ease across the jump, not cut"
        )
    }

    func testTinyTripNeverZoomsInPastTheSpanFloor() throws {
        // straightRoute is ~1 km — its fitting span is under camera_span_m, so
        // the floor holds and a short trip is not framed absurdly tight.
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
