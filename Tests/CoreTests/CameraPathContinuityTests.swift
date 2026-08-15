import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// Dead-zone follow camera (Chiu 2026-08-01). Split from `CameraPathTests.swift`
/// (lint length only, Chiu 2026-08-07) — shares its fixtures (`straightRoute`,
/// `longRoute`, `exportConfig`), so those became internal there rather than
/// `private`.
extension CameraPathTests {
    /// **The continuity rule, at unit scale.** The camera is never placed, only
    /// moved, so consecutive frames always share most of their ground. This is
    /// the contract that replaced "one fixed frame per act" — acts framing
    /// themselves is exactly how the camera came to cut between unrelated views.
    func testCameraNeverJumpsBetweenConsecutiveFrames() throws {
        let config = exportConfig()
        let path = try XCTUnwrap(CameraPath(route: longRoute, stops: [longRoute[5]], config: config))

        let step = 1.0 / Double(config.fps)
        var previous = path.cameraFrame(atTime: 0)
        for frame in 1..<path.frameCount {
            let now = path.cameraFrame(atTime: Double(frame) * step)
            let moved = Geo.distanceM(
                latA: previous.centerLat, lonA: previous.centerLon,
                latB: now.centerLat, lonB: now.centerLon
            )
            XCTAssertLessThan(
                moved, now.spanM * 0.5,
                "frame \(frame) moved \(moved) m across a \(now.spanM) m window — that is a cut, not a move"
            )
            previous = now
        }
    }

    /// The span is fixed for the whole trip, and the body never zooms. Only the
    /// opening and the closing reveal may change it, and both are outside the
    /// journey — this is the product rule that keeps the world measurable.
    func testBodySpanNeverChangesWhileTravelling() throws {
        let config = exportConfig()
        let path = try XCTUnwrap(CameraPath(route: longRoute, stops: [longRoute[5]], config: config))
        let body = path.cameraFrame(atTime: (path.durationS) / 2).spanM
        for time in stride(from: path.openingS, through: path.durationS - config.endCardS - 0.1, by: 0.1) {
            XCTAssertEqual(path.cameraFrame(atTime: time).spanM, body, accuracy: 1e-6,
                           "the body span moved at t=\(time)")
        }
    }

    /// While the journey's leading edge is inside the dead zone the camera does
    /// not move *at all*. Without this the map slides under a pinned cursor,
    /// which is the GPS-viewport feel the redesign exists to remove.
    ///
    /// Asserted as "there is a real stretch of stillness", not "frame 1 matches
    /// frame 0": where the dead zone is entered depends on the world clamp and on
    /// where the route starts inside its own bounding box, and pinning the test to
    /// one instant tests the fixture rather than the behaviour.
    func testCameraHoldsCompletelyStillWhileSubjectCrossesTheDeadZone() throws {
        let config = exportConfig()
        let path = try XCTUnwrap(CameraPath(route: longRoute, stops: [], config: config))

        let step = 1.0 / Double(config.fps)
        var longestStill = 0.0
        var run = 0.0
        var previous = path.cameraFrame(atTime: 0)
        for frame in 1..<path.frameCount {
            let now = path.cameraFrame(atTime: Double(frame) * step)
            let moved = Geo.distanceM(
                latA: previous.centerLat, lonA: previous.centerLon,
                latB: now.centerLat, lonB: now.centerLon
            )
            run = moved < 0.01 ? run + step : 0
            longestStill = max(longestStill, run)
            previous = now
        }
        XCTAssertGreaterThan(
            longestStill, 1.0,
            "the dead zone should buy at least a second of a genuinely motionless map"
        )
    }

    /// A short trip is framed by its own extent rather than by the pan-rate
    /// formula: the ceiling binds, the whole route is on screen, and the body
    /// camera is static — the 2026-07-25 "held still" behaviour, now a
    /// consequence of the span rule rather than a special case.
    func testCompactTripFallsBackToAStaticWholeRouteFrame() throws {
        let config = exportConfig()
        let path = try XCTUnwrap(CameraPath(route: straightRoute, stops: [], config: config))
        let first = path.cameraFrame(atTime: 0)
        for time in stride(from: 0.0, through: config.targetDurationS, by: 0.5) {
            let frame = path.cameraFrame(atTime: time)
            let drift = Geo.distanceM(
                latA: first.centerLat, lonA: first.centerLon,
                latB: frame.centerLat, lonB: frame.centerLon
            )
            XCTAssertLessThan(drift, frame.spanM * 0.25,
                              "a route this short should barely move the camera at all (t=\(time))")
        }
        XCTAssertEqual(first.spanM, config.cameraSpanM, accuracy: 1e-6,
                       "a ~1 km route floors at camera_span_m rather than framing absurdly tight")
    }

    /// Even a genuine 200 km leap is crossed continuously. The detector still
    /// reports it — a ferry is a ferry — but reporting it is not permission to
    /// teleport the frame.
    func testLargeJumpIsStillCrossedWithoutBreakingContinuity() throws {
        let config = exportConfig()
        let near = (0...10).map { CameraPath.Point(lat: -32.0 + Double($0) * 0.001, lon: 115.75) }
        let far = (0...10).map { CameraPath.Point(lat: -30.2 + Double($0) * 0.001, lon: 115.75) }
        let path = try XCTUnwrap(CameraPath(route: near + far, stops: [], config: config))

        XCTAssertEqual(path.permittedCutTimesS.count, 1, "the leap is still detected")
        let step = 1.0 / Double(config.fps)
        var previous = path.cameraFrame(atTime: 0)
        for frame in 1..<path.frameCount {
            let now = path.cameraFrame(atTime: Double(frame) * step)
            let moved = Geo.distanceM(
                latA: previous.centerLat, lonA: previous.centerLon,
                latB: now.centerLat, lonB: now.centerLon
            )
            XCTAssertLessThan(moved, now.spanM * 0.5, "the camera cut across the leap at frame \(frame)")
            previous = now
        }
    }

    /// **The opening is continuous motion, end to end** (Chiu 2026-08-01).
    ///
    /// The freeze at 0:05–0:08 outlived several rounds of tuning because it was
    /// never a duration problem: during a wide beat the journey has not started,
    /// so there is nothing on screen that *can* move, and shortening a hold only
    /// makes the dead frame shorter. The fix is that no held beat is allowed to
    /// last long enough to read as a stall — the same continuity philosophy the
    /// body camera follows, applied to the opening.
    func testOpeningHasNoHeldBeatLongEnoughToReadAsAStall() throws {
        let export = exportConfig()
        // An opening only exists when there is an establishing extent to open on.
        let line = try XCTUnwrap(CameraPath(
            route: longRoute, stops: [longRoute[5]], config: export,
            totalDurationS: export.totalDurationMinS,
            establishing: RecapBounds(minLat: -33, minLon: 115, maxLat: -31, maxLon: 117),
            openingS: export.openingCountryS + export.openingRegionalS + 2 * export.zoomTransitionS
        ))
        let step = 1.0 / Double(export.fps)

        var longestStill = 0.0
        var run = 0.0
        var previous = line.cameraFrame(atTime: 0)
        // From the end of the title card: a still frame *with the title on it* is
        // the title beat working. Dead air is stillness after the card is gone.
        for time in stride(from: export.titleCardS + step, through: line.openingS, by: step) {
            let frame = line.cameraFrame(atTime: time)
            let moved = Geo.distanceM(
                latA: previous.centerLat, lonA: previous.centerLon,
                latB: frame.centerLat, lonB: frame.centerLon
            )
            // "Still" means neither panning nor zooming perceptibly.
            if moved < frame.spanM * 1e-4, abs(frame.spanM - previous.spanM) < frame.spanM * 1e-4 {
                run += step
            } else {
                run = 0
            }
            longestStill = max(longestStill, run)
            previous = frame
        }
        XCTAssertLessThanOrEqual(
            longestStill, 1.05,
            "the opening sits still for \(longestStill)s after the title card — "
                + "capped at ~1 s so it never reads as a freeze"
        )
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
