import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// Golden-frame gate for the render-layers pipeline (§4.5 step 2): the flat
/// provider makes `RecapTrip` → `LinearTimeline` → `FrameCompositor`
/// deterministic, so these tests pin down frame composition by sampling pixels
/// — same trip, same config, same bytes. The subject + route survive from the
/// old compositor gate; the stop frames are the new two-beat (pin/label → deck)
/// behavior.
final class RecapFrameTests: RecapRenderTestCase {
    // MARK: - Subject + trail

    func testMidTripFrameShowsSubjectTraveledTrailAndUntraveledAhead() async throws {
        let config = exportConfig()
        let timeline = try makeTimeline(makeTrip(config: config), config: config)
        let compositor = makeCompositor(timeline)
        // Halfway: the camera sits mid-route (close follow), trail behind it.
        let time = config.targetDurationS / 2
        let frame = try await renderFrame(timeline, compositor, at: time, config: config)

        let centerX = widthPx / 2
        let centerY = heightPx / 2
        try assertVehiclePresent(frame, col: centerX, row: centerY, "vehicle subject rides the camera center")
        // Clear of the vehicle: south (larger y) is traveled, north is bare map.
        let clear = vehicleHalfPx + 20
        try assertPixel(frame, col: centerX, row: centerY + clear, is: routeRGB, "traveled trail behind the subject")
        try assertPixel(frame, col: centerX, row: centerY - clear, is: backgroundRGB, "route ahead not drawn yet")
        try assertPixel(frame, col: 10, row: 10, is: backgroundRGB, "off-route corner is base map")
    }

    func testMarkerScreenRotationIsHeadingMinusBearing() {
        // North-up map (bearing 0): the marker rotates to the travel heading.
        XCTAssertEqual(VehicleMarker.screenRotationDegrees(heading: 90, bearing: 0), 90, accuracy: 1e-9)
        // Heading-up map (bearing == heading in the follow body): points up.
        XCTAssertEqual(VehicleMarker.screenRotationDegrees(heading: 210, bearing: 210), 0, accuracy: 1e-9)
        // Wraps into [0, 360): 10 − 40 = −30 → 330.
        XCTAssertEqual(VehicleMarker.screenRotationDegrees(heading: 10, bearing: 40), 330, accuracy: 1e-9)
    }

    /// Sampled in the close-follow body (constant span) so trail growth reads as
    /// pixel growth without the wide→close zoom changing the scale.
    func testTraveledTrailGrowsMonotonicallyAcrossFrames() async throws {
        let config = exportConfig()
        let timeline = try makeTimeline(makeTrip(config: config), config: config)
        let compositor = makeCompositor(timeline)

        var previousCount = -1
        for time in stride(from: 2.0, through: 4.0, by: 0.5) {
            let frame = try await renderFrame(timeline, compositor, at: time, config: config)
            let count = try colorCount(frame, matching: routeRGB)
            XCTAssertGreaterThan(count, previousCount, "trail should keep growing at t=\(time)")
            previousCount = count
        }
    }

    // MARK: - Stop scene (two-beat: pin/label → photo deck)

    /// A photo stop plays two beats — the pin/name lead, then the photo card —
    /// and a photoless stop (the photos-off / route-only path) shows neither.
    func testStopSceneLeadsWithTheLabelThenTheDeckWhilePhotolessStopStaysBare() async throws {
        let config = exportConfig()
        let green = try makeSolidImage(red: 0, green: 1, blue: 0)
        let timeline = try makeTimeline(
            makeTrip(stops: [StopSpec(routeIndex: 5, name: "Busselton", photos: [.asset("a")])], config: config),
            config: config
        )
        let compositor = makeCompositor(timeline, resolver: StubResolver { _ in green })

        // Beat 1: the label is up and no photo has arrived yet.
        let lead = try XCTUnwrap(
            stride(from: 0.0, through: timeline.durationS, by: 0.05).first { time in
                hasStopLabel(timeline.overlayContents(atTime: time))
            }, "the stop label must lead the scene"
        )
        XCTAssertNil(activePhotoDeck(timeline.overlayContents(atTime: lead)), "no card during the lead beat")

        // Beat 2: the card is up, and it has taken the stop's name over from the
        // lead-in label (which has faded out by then).
        let peak = try deckPeakTime(timeline)
        let deck = try XCTUnwrap(activePhotoDeck(timeline.overlayContents(atTime: peak)))
        XCTAssertEqual(deck.name, "Busselton", "the card carries the stop identity in beat 2")
        XCTAssertFalse(hasStopLabel(timeline.overlayContents(atTime: peak)), "the lead label has handed off")
        let frame = try await renderFrame(timeline, compositor, at: peak, config: config)
        let greenRGB = RGB(red: 0, green: 255, blue: 0)
        XCTAssertGreaterThan(
            try colorCount(frame, matching: greenRGB), 200, "deck hero photo opens at the stop"
        )

        // Photos off → the stop still holds, but no label and no deck appear.
        let bare = try makeTimeline(makeTrip(stops: [StopSpec(routeIndex: 5)], config: config), config: config)
        for time in stride(from: 0.0, through: bare.durationS, by: 0.25) {
            XCTAssertNil(activePhotoDeck(bare.overlayContents(atTime: time)), "no photos → no deck at t=\(time)")
            XCTAssertFalse(hasStopLabel(bare.overlayContents(atTime: time)), "no photos → no label at t=\(time)")
        }
    }

    /// §5 zoom-in reveal (Chiu 2026-07-25): the card opens from ~0.30 to ~0.50
    /// frame width as the shot pushes in — it must actually grow on screen, must
    /// rotate through the stop's photos (highlight leads), and must never take
    /// the whole frame: the map and trail stay visible around its edges.
    func testPhotoDeckRevealGrowsRotatesAndLeavesTheMapVisible() async throws {
        let config = exportConfig()
        let green = RGB(red: 0, green: 255, blue: 0)
        let blue = RGB(red: 0, green: 0, blue: 255)
        let refA = PhotoRef.asset("a"), refB = PhotoRef.asset("b")
        let greenImage = try makeSolidImage(red: 0, green: 1, blue: 0)
        let blueImage = try makeSolidImage(red: 0, green: 0, blue: 1)
        let timeline = try makeTimeline(
            makeTrip(stops: [StopSpec(routeIndex: 5, name: "Deck Stop", photos: [refA, refB])], config: config),
            config: config
        )
        let compositor = makeCompositor(timeline, resolver: StubResolver { $0 == refA ? greenImage : blueImage })
        let samples = deckSamples(timeline)
        XCTAssertFalse(samples.isEmpty, "the deck must be present through the stop")

        func photoArea(atTime time: Double) async throws -> Int {
            let frame = try await renderFrame(timeline, compositor, at: time, config: config)
            return try colorCount(frame, matching: green) + colorCount(frame, matching: blue)
        }

        // Compare at full opacity, so this measures the reveal's *size* growth
        // rather than the cross-fade.
        let opaque = samples.filter { $0.deck.opacity > 0.99 }
        let early = try XCTUnwrap(opaque.first), late = try XCTUnwrap(opaque.last)
        XCTAssertLessThan(early.deck.reveal, 0.5, "the card starts near its minimum size")
        XCTAssertGreaterThan(late.deck.reveal, 0.9, "the card finishes near its maximum size")
        let earlyArea = try await photoArea(atTime: early.time)
        let lateArea = try await photoArea(atTime: late.time)
        XCTAssertGreaterThan(lateArea, Int(Double(earlyArea) * 1.3), "the photo must visibly grow through the reveal")

        // The card never swallows the frame — the souvenir map reads around it.
        XCTAssertLessThan(
            Double(lateArea) / Double(widthPx * heightPx), 0.35,
            "the fully revealed card must still leave the map visible around it"
        )

        // Rotation: the first (highlight) photo leads, the second follows. The
        // card tracks the vehicle now, so assert which photo is on screen rather
        // than probing a fixed point.
        let focus0 = try XCTUnwrap(opaque.first { $0.deck.focusIndex == 0 }).time
        let focus1 = try XCTUnwrap(opaque.first { $0.deck.focusIndex == 1 }).time
        let firstFrame = try await renderFrame(timeline, compositor, at: focus0, config: config)
        XCTAssertGreaterThan(try colorCount(firstFrame, matching: green), 200, "highlight photo leads the deck")
        XCTAssertEqual(try colorCount(firstFrame, matching: blue), 0, "only the focused photo shows")
        let secondFrame = try await renderFrame(timeline, compositor, at: focus1, config: config)
        XCTAssertGreaterThan(try colorCount(secondFrame, matching: blue), 200, "deck rotates to the next photo")

        // Deterministic: the same deck frame renders byte-identically.
        let again = try await renderFrame(timeline, compositor, at: focus0, config: config)
        XCTAssertEqual(
            try XCTUnwrap(pixels(firstFrame).data as Data?),
            try XCTUnwrap(pixels(again).data as Data?),
            "deck rendering must stay byte-deterministic"
        )
    }

    // MARK: - Cross-fade + determinism

    func testCrossFadeBlendsBackgroundsAndKeepsSubjectOnRoute() async throws {
        let config = exportConfig()
        let timeline = try makeTimeline(makeTrip(config: config), config: config)
        let compositor = makeCompositor(timeline)
        let time = config.targetDurationS / 2
        let cameraFrame = timeline.cameraFrame(atTime: time)
        let request = CameraFrame(
            centerLat: cameraFrame.centerLat, centerLon: cameraFrame.centerLon,
            spanM: cameraFrame.spanM, bearing: cameraFrame.bearing
        )
        // Two keyframes at the same camera frame — the projections match, so the
        // subject still lands at center while the fills blend.
        let dark = try await FlatSnapshotProvider(red: 0.2, green: 0.2, blue: 0.2).snapshot(
            request, map: MapState(), widthPx: widthPx, heightPx: heightPx
        )
        let light = try await FlatSnapshotProvider().snapshot(
            request, map: MapState(), widthPx: widthPx, heightPx: heightPx
        )
        let frame = try compositor.render(
            atTime: time, background: RecapBackground(current: light, previous: dark, blend: 0.5)
        )

        try assertVehiclePresent(frame, col: widthPx / 2, row: heightPx / 2, "vehicle subject survives cross-fade")
        let corner = try pixel(frame, col: 10, row: 10)
        XCTAssertEqual(corner.red, (backgroundRGB.red + 51) / 2, accuracy: 4, "corner should be a 50/50 blend")
    }

    func testRenderIsDeterministicAcrossIndependentPipelines() async throws {
        let config = exportConfig()

        func renderOnce() async throws -> Data {
            let timeline = try makeTimeline(
                makeTrip(stops: [StopSpec(routeIndex: 5, name: "Stop")], config: config), config: config
            )
            let compositor = makeCompositor(timeline)
            let frame = try await renderFrame(timeline, compositor, at: config.targetDurationS / 2, config: config)
            return try XCTUnwrap(pixels(frame).data as Data?)
        }

        let first = try await renderOnce()
        let second = try await renderOnce()
        XCTAssertEqual(first, second, "identical inputs must produce byte-identical frames")
    }

    // MARK: - Render loop gates

    func testLoopDeliversEveryFrameInOrderWithOneSnapshotPerKeyframe() async throws {
        // 2 s × 5 fps = 10 frames; keyframe every 3 frames → keyframes 0–3
        // plus the bracketing 4th: exactly 5 snapshots for 10 frames.
        let config = exportConfig(targetDurationS: 2, fps: 5, keyframeIntervalFrames: 3)
        let timeline = try makeTimeline(makeTrip(config: config), config: config)
        let compositor = makeCompositor(timeline)
        let provider = CountingProvider()
        let loop = RecapRenderLoop(timeline: timeline, compositor: compositor, provider: provider, config: config)

        var delivered: [Int] = []
        try await loop.renderFrames { frame, image in
            XCTAssertEqual(image.width, self.widthPx)
            XCTAssertEqual(image.height, self.heightPx)
            delivered.append(frame)
            return true
        }

        XCTAssertEqual(delivered, Array(0..<timeline.frameCount))
        XCTAssertEqual(provider.requestCount, 5, "keyframe cache should collapse snapshot requests")
    }

    func testLoopStopsWhenConsumerCancels() async throws {
        let config = exportConfig(targetDurationS: 2, fps: 5, keyframeIntervalFrames: 3)
        let timeline = try makeTimeline(makeTrip(config: config), config: config)
        let compositor = makeCompositor(timeline)
        let loop = RecapRenderLoop(timeline: timeline, compositor: compositor, provider: CountingProvider(), config: config)

        var delivered = 0
        try await loop.renderFrames { frame, _ in
            delivered += 1
            return frame < 3
        }
        XCTAssertEqual(delivered, 4, "loop should stop right after the consumer declines")
    }

    /// End-to-end over a real engine-produced trip: the perth fixture renders
    /// through the full loop and stays deterministic.
    func testPerthReplayRendersDeterministically() async throws {
        let engine = try GPXReplay.run(fixture: "perth_margaret_river_day1.gpx")
        let coords = engine.segments.flatMap(\.points).map { RecapCoordinate(lat: $0.lat, lon: $0.lon) }
        let config = exportConfig(targetDurationS: 2, fps: 5, keyframeIntervalFrames: 3)
        let stops = engine.stops.enumerated().map { index, stop in
            RecapTrip.Stop(
                coordinate: RecapCoordinate(lat: stop.lat, lon: stop.lon),
                name: "Stop \(index + 1)", dayLabel: "Day 1", detail: nil, photos: [], dwellS: config.stopHoldS
            )
        }
        let trip = RecapTrip(
            route: coords, stops: stops, title: "Perth", subtitle: "Day 1",
            statsLines: [], callToAction: "", shareURL: "kamome://route/perth"
        )
        let timeline = try makeTimeline(trip, config: config)
        let compositor = makeCompositor(timeline)

        func lastFrame() async throws -> Data {
            let loop = RecapRenderLoop(
                timeline: timeline, compositor: compositor, provider: FlatSnapshotProvider(), config: config
            )
            var last: Data?
            try await loop.renderFrames { _, image in
                last = image.dataProvider?.data as Data?
                return true
            }
            return try XCTUnwrap(last)
        }

        let first = try await lastFrame()
        let second = try await lastFrame()
        XCTAssertEqual(first, second, "fixture render must be reproducible frame for frame")
    }

    // MARK: - Deck sampling helpers

    private struct DeckSample {
        let time: Double
        let deck: RecapPhotoDeck
    }

    /// Fine-samples the (single-stop) timeline for every instant its photo deck
    /// is active, so a test can locate the grow / peak / shrink and focus beats
    /// without recomputing the window math.
    private func deckSamples(_ timeline: LinearTimeline, dt: Double = 0.05) -> [DeckSample] {
        var samples: [DeckSample] = []
        var time = 0.0
        while time <= timeline.durationS {
            if let deck = activePhotoDeck(timeline.overlayContents(atTime: time)) {
                samples.append(DeckSample(time: time, deck: deck))
            }
            time += dt
        }
        return samples
    }

    /// The most-open, fully-opaque instant of the deck — the frame to probe when
    /// a test wants the card at its largest.
    private func deckPeakTime(_ timeline: LinearTimeline) throws -> Double {
        try XCTUnwrap(deckSamples(timeline).max { $0.deck.reveal < $1.deck.reveal }).time
    }
}
