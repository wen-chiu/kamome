import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// §4.5 step 1: speed-warped camera path. Synthetic routes pin down the
/// timing contract; the perth fixture proves the path survives a real
/// engine-produced trip.
final class CameraPathTests: XCTestCase {
    /// 1 km straight line, 11 evenly spaced vertices along a meridian.
    ///
    /// Internal, not private: shared with the dead-zone/continuity tests in
    /// `CameraPathContinuityTests.swift`.
    let straightRoute: [CameraPath.Point] = (0...10).map {
        CameraPath.Point(lat: -32.0 + Double($0) * 0.0009, lon: 115.75)
    }

    func exportConfig(
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
            crossingBeatS: 4.0,
            crossingApexPadding: 1.5,
            followHeadingUp: followHeadingUp,
            cameraPanWindowFractionPerS: 0.35, cameraDeadZoneFraction: 0.7, cameraSafeZoneFraction: 0.8,
            cameraResponsiveness: 6.0, endRevealS: 2.5, endRevealPadding: 1.9, endCardStyle: "full",
            deckPhotoHoldS: 0.8, deckPhotoMinHoldS: 0.2,
            deckZoomS: 0.5,
            deckLabelLeadS: 0.6, subjectParkS: 0.4,
            openingCountryS: 1.0, openingRegionalS: 1.0, countryViewPadding: 2.2, firstStopDwellScale: 0.55,
            openingCollapseZoomRatio: 1.25, openingCollapseDriftFraction: 0.15,
            stopDwellMinS: 6, stopDwellMaxS: 25,
            totalDurationMinS: 60, totalDurationMaxS: 90,
            keyframeIntervalFrames: 15,
            snapshotStationMaxMagnification: 1.5,
            snapshotStationPadding: 1.03,
            crossingFlightMaxLongitudeDeg: 70,
            subjectLengthPx: 300,
            titleCardS: 2.5,
            endCardS: 3,
            videoBitrateMbps: 5,
            stopWeightingEnabled: false, waypointMaxPhotos: 2, waypointMaxDwellS: 900, waypointHoldS: 0.8,
            uncappedPhotoHoldS: 1.0,
            allocationZeroShare: 0.4, allocationOneShare: 0.3,
            allocationTwoShare: 0.2, allocationMaxPhotos: 3, favoriteWeight: 3.0,
            tierTopShare: 0.15,
            tierStandardPhotos: 3, tierTopPhotos: 5,
            earnedStopsFloor: 8, earnedStopsCap: 21,
            earnedStopsPerDoubling: 7, earnedStopsReferenceTripStops: 10,
            recapMode: .highlight
        )
    }

    /// A route large enough that the whole-trip fitting span exceeds the close
    /// follow span, so the wide↔close difference is observable.
    let longRoute: [CameraPath.Point] = (0...10).map {
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

}
