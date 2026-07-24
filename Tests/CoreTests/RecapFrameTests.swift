import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// Golden-frame gate for §4.5 step 2: the flat provider makes the whole
/// pipeline deterministic, so these tests pin down frame composition by
/// sampling pixels — same trip, same config, same bytes.
final class RecapFrameTests: RecapRenderTestCase {
    // MARK: - Compositor gates

    func testMidTripFrameShowsVehicleMarkerTraveledTrailAndUntraveledNorth() async throws {
        let config = exportConfig()
        let (path, compositor) = try makePipeline(config: config)
        // Halfway: the camera sits mid-route, trail behind it to the south.
        let time = config.targetDurationS / 2
        let background = try await snapshot(centeredAt: path.position(atTime: time), config: config)
        let frame = try compositor.render(atTime: time, background: RecapBackground(current: background))

        let centerX = widthPx / 2
        let centerY = heightPx / 2
        try assertPixel(frame, col: centerX, row: centerY, is: markerRGB, "vehicle marker rides the camera center")
        // South of the marker (larger y) is traveled; north is still bare map.
        try assertPixel(frame, col: centerX, row: centerY + 25, is: routeRGB, "traveled trail behind the vehicle")
        try assertPixel(frame, col: centerX, row: centerY - 25, is: backgroundRGB, "route ahead not drawn yet")
        try assertPixel(frame, col: 10, row: 10, is: backgroundRGB, "off-route corner is base map")
    }

    /// The marker points along the route: on a north route its long axis is
    /// vertical, on an east route it rotates to horizontal (screen rotation =
    /// heading − bearing). Verified by the bounding box of the car's body pixels
    /// — its long axis is the taller/wider extent.
    func testVehicleMarkerRotatesToHeading() async throws {
        let config = exportConfig()

        func markerExtent(route: [CameraPath.Point]) async throws -> (rows: Int, cols: Int) {
            let path = try XCTUnwrap(CameraPath(route: route, stops: [], config: config))
            let compositor = RecapFrameCompositor(
                path: path, events: [], stopCards: [],
                widthPx: widthPx, heightPx: heightPx, style: opaqueCardStyle
            )
            let time = config.targetDurationS / 2
            let background = try await snapshot(centeredAt: path.position(atTime: time), config: config)
            let frame = try compositor.render(atTime: time, background: RecapBackground(current: background))
            // Bounding box of the marker-red body pixels around center.
            var minRow = heightPx, maxRow = 0, minCol = widthPx, maxCol = 0
            for row in (heightPx / 2 - 40)...(heightPx / 2 + 40) {
                for col in (widthPx / 2 - 40)...(widthPx / 2 + 40) {
                    let sample = try pixel(frame, col: col, row: row)
                    guard abs(sample.red - markerRGB.red) <= 3,
                          abs(sample.green - markerRGB.green) <= 3,
                          abs(sample.blue - markerRGB.blue) <= 3 else { continue }
                    minRow = min(minRow, row); maxRow = max(maxRow, row)
                    minCol = min(minCol, col); maxCol = max(maxCol, col)
                }
            }
            return (maxRow - minRow, maxCol - minCol)
        }

        let north = try await markerExtent(route: route)  // meridian: heading 0°
        let eastRoute = (0...10).map { CameraPath.Point(lat: -32.0, lon: 115.75 + Double($0) * 0.0009) }
        let east = try await markerExtent(route: eastRoute)  // heading 90°

        XCTAssertGreaterThan(north.rows, north.cols, "north-bound car points up (long axis vertical)")
        XCTAssertGreaterThan(east.cols, east.rows, "east-bound car rotates to point right")
    }

    func testMarkerScreenRotationIsHeadingMinusBearing() {
        // North-up map (bearing 0): the marker rotates to the travel heading.
        XCTAssertEqual(VehicleMarker.screenRotationDegrees(heading: 90, bearing: 0), 90, accuracy: 1e-9)
        // Heading-up map (bearing == heading in the follow body): points up.
        XCTAssertEqual(VehicleMarker.screenRotationDegrees(heading: 210, bearing: 210), 0, accuracy: 1e-9)
        // Wraps into [0, 360): 10 − 40 = −30 → 330.
        XCTAssertEqual(VehicleMarker.screenRotationDegrees(heading: 10, bearing: 40), 330, accuracy: 1e-9)
    }

    func testTraveledTrailGrowsMonotonicallyAcrossFrames() async throws {
        let config = exportConfig()
        let (path, compositor) = try makePipeline(config: config)

        var previousCount = -1
        for time in stride(from: 1.0, through: 5.0, by: 1.0) {
            let background = try await snapshot(centeredAt: path.position(atTime: time), config: config)
            let frame = try compositor.render(atTime: time, background: RecapBackground(current: background))
            let count = try colorCount(frame, matching: routeRGB)
            XCTAssertGreaterThan(count, previousCount, "trail should keep growing at t=\(time)")
            previousCount = count
        }
    }

    func testStopHoldShowsCardAndPhotosOffHidesIt() async throws {
        let config = exportConfig()
        let card = RecapFrameCompositor.StopCard(name: "Busselton Jetty", dayLabel: "Day 1")
        let (path, compositor) = try makePipeline(
            stops: [route[5]], stopCards: [card], config: config
        )
        let hold = try XCTUnwrap(path.holds.first)
        let time = (hold.startS + hold.endS) / 2
        let background = try await snapshot(centeredAt: path.position(atTime: time), config: config)
        let frame = try compositor.render(atTime: time, background: RecapBackground(current: background))

        // Inside the card's right edge — clear of photo, name text, and badge.
        let cardX = widthPx - 25
        let cardY = heightPx - 40
        try assertPixel(frame, col: cardX, row: cardY, is: cardRGB, "stop card visible during hold")

        // S5 photos toggle off → no photo overlays (stop cards).
        let (_, plainCompositor) = try makePipeline(
            stops: [route[5]], photosEnabled: false, stopCards: [card], config: config
        )
        let plain = try plainCompositor.render(atTime: time, background: RecapBackground(current: background))
        try assertPixel(plain, col: cardX, row: cardY, is: backgroundRGB, "photos off leaves bare map")
    }

    /// stop.kind rendering (ADR 2026-07-18 stop-kind): a walk-visit card
    /// carries a detail line (walking duration); a dwell card doesn't.
    func testWalkVisitDetailLineDrawsDeterministically() async throws {
        let config = exportConfig()

        func render(detail: String?) async throws -> Data {
            let card = RecapFrameCompositor.StopCard(name: "紫雲巖", dayLabel: "Day 1", detail: detail)
            let (path, compositor) = try makePipeline(stops: [route[5]], stopCards: [card], config: config)
            let hold = try XCTUnwrap(path.holds.first)
            let time = (hold.startS + hold.endS) / 2
            let background = try await snapshot(centeredAt: path.position(atTime: time), config: config)
            let frame = try compositor.render(atTime: time, background: RecapBackground(current: background))
            return try XCTUnwrap(pixels(frame).data as Data?)
        }

        let dwellCard = try await render(detail: nil)
        let walkVisitCard = try await render(detail: "步行 21 分鐘")
        XCTAssertNotEqual(dwellCard, walkVisitCard, "the detail line must actually draw")
        let repeated = try await render(detail: "步行 21 分鐘")
        XCTAssertEqual(walkVisitCard, repeated, "detail rendering must stay byte-deterministic")
    }

    /// §5 (Chiu 2026-07-23): the deck enlarges the photo, rotates through the
    /// stop's photos (highlight leads), then shrinks back. The scale envelope
    /// blooms and recedes; the shown photo advances through the deck.
    func testPhotoDeckEnlargesRotatesThroughPhotosAndReturns() async throws {
        let config = exportConfig()
        let green = RGB(red: 0, green: 255, blue: 0)
        let blue = RGB(red: 0, green: 0, blue: 255)
        let card = RecapFrameCompositor.StopCard(
            name: "Deck Stop", dayLabel: "Day 1",
            photos: [try makeSolidImage(red: 0, green: 1, blue: 0), try makeSolidImage(red: 0, green: 0, blue: 1)]
        )
        let (path, compositor) = try makePipeline(stops: [route[5]], stopCards: [card], config: config)
        let hold = try XCTUnwrap(path.holds.first)
        let deck = RecapDeck()  // matches the compositor default: zoom 0.5, hold 0.8
        let length = hold.endS - hold.startS
        let zoom = min(deck.zoomS, length * 0.4)

        func photoArea(atTime time: Double) async throws -> Int {
            let background = try await snapshot(centeredAt: path.position(atTime: time), config: config)
            let frame = try compositor.render(atTime: time, background: RecapBackground(current: background))
            return try colorCount(frame, matching: green) + colorCount(frame, matching: blue)
        }

        // Envelope: tiny at the edges of the window, large at the peak.
        let growArea = try await photoArea(atTime: hold.startS + 0.02)
        let peakArea = try await photoArea(atTime: (hold.startS + hold.endS) / 2)
        let shrinkArea = try await photoArea(atTime: hold.endS - 0.02)
        XCTAssertGreaterThan(peakArea, growArea * 4, "photo should bloom large at the peak")
        XCTAssertGreaterThan(peakArea, shrinkArea * 4, "photo should shrink back toward the map")

        // Rotation: the first (highlight) photo leads, the second follows.
        let rotateStart = hold.startS + zoom
        let slot = (hold.endS - zoom - rotateStart) / 2
        func frame(atTime time: Double) async throws -> CGImage {
            let background = try await snapshot(centeredAt: path.position(atTime: time), config: config)
            return try compositor.render(atTime: time, background: RecapBackground(current: background))
        }
        let row = Int(Double(heightPx) * 0.45)
        let firstFrame = try await frame(atTime: rotateStart + slot * 0.5)
        try assertPixel(firstFrame, col: widthPx / 2, row: row, is: green, "highlight photo leads the deck")
        let secondFrame = try await frame(atTime: rotateStart + slot * 1.5)
        try assertPixel(secondFrame, col: widthPx / 2, row: row, is: blue, "deck rotates to the next photo")

        // Deterministic: the same deck frame renders byte-identically.
        let again = try await frame(atTime: rotateStart + slot * 0.5)
        XCTAssertEqual(
            try XCTUnwrap(pixels(firstFrame).data as Data?),
            try XCTUnwrap(pixels(again).data as Data?),
            "deck rendering must stay byte-deterministic"
        )
    }

    func testCrossFadeBlendsBackgroundsAndKeepsOverlayOnRoute() async throws {
        let config = exportConfig()
        let (path, compositor) = try makePipeline(config: config)
        let time = config.targetDurationS / 2
        let dark = try await FlatSnapshotProvider(red: 0.2, green: 0.2, blue: 0.2).snapshot(
            CameraFrame(
                centerLat: path.position(atTime: time).lat, centerLon: path.position(atTime: time).lon,
                spanM: config.cameraSpanM, bearing: 0
            ),
            map: MapState(), widthPx: widthPx, heightPx: heightPx
        )
        let light = try await snapshot(centeredAt: path.position(atTime: time), config: config)
        let frame = try compositor.render(
            atTime: time,
            background: RecapBackground(current: light, previous: dark, blend: 0.5)
        )

        // Same projection on both sides, so the marker still hits center...
        try assertPixel(frame, col: widthPx / 2, row: heightPx / 2, is: markerRGB, "vehicle marker survives cross-fade")
        // ...and the empty corner is the halfway blend of the two fills.
        let corner = try pixel(frame, col: 10, row: 10)
        XCTAssertEqual(corner.red, (backgroundRGB.red + 51) / 2, accuracy: 4, "corner should be a 50/50 blend")
    }

    func testRenderIsDeterministicAcrossIndependentPipelines() async throws {
        let config = exportConfig()

        func renderOnce() async throws -> Data {
            let (path, compositor) = try makePipeline(
                stops: [route[5]],
                stopCards: [RecapFrameCompositor.StopCard(name: "Stop", dayLabel: "Day 1")],
                config: config
            )
            let hold = try XCTUnwrap(path.holds.first)
            let background = try await snapshot(centeredAt: path.position(atTime: hold.startS), config: config)
            let frame = try compositor.render(atTime: hold.startS, background: RecapBackground(current: background))
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
        let (path, compositor) = try makePipeline(config: config)
        let provider = CountingProvider()
        let loop = RecapRenderLoop(path: path, compositor: compositor, provider: provider, config: config)

        var delivered: [Int] = []
        try await loop.renderFrames { frame, image in
            XCTAssertEqual(image.width, self.widthPx)
            XCTAssertEqual(image.height, self.heightPx)
            delivered.append(frame)
            return true
        }

        XCTAssertEqual(delivered, Array(0..<path.frameCount))
        XCTAssertEqual(provider.requestCount, 5, "keyframe cache should collapse snapshot requests")
    }

    func testLoopStopsWhenConsumerCancels() async throws {
        let config = exportConfig(targetDurationS: 2, fps: 5, keyframeIntervalFrames: 3)
        let (path, compositor) = try makePipeline(config: config)
        let loop = RecapRenderLoop(path: path, compositor: compositor, provider: CountingProvider(), config: config)

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
        let tripRoute = engine.segments.flatMap(\.points).map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
        let stops = engine.stops.map { CameraPath.Point(lat: $0.lat, lon: $0.lon) }
        let config = exportConfig(targetDurationS: 2, fps: 5, keyframeIntervalFrames: 3)
        let path = try XCTUnwrap(CameraPath(route: tripRoute, stops: stops, config: config))
        let events = OverlayTimeline.build(holds: path.holds, config: config, photosEnabled: true)
        let cards = stops.indices.map { index in
            RecapFrameCompositor.StopCard(name: "Stop \(index + 1)", dayLabel: "Day 1")
        }
        let compositor = RecapFrameCompositor(
            path: path, events: events, stopCards: cards,
            widthPx: widthPx, heightPx: heightPx, style: opaqueCardStyle
        )

        func lastFrame() async throws -> Data {
            let loop = RecapRenderLoop(
                path: path, compositor: compositor, provider: FlatSnapshotProvider(), config: config
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
}
