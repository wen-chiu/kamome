import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// Golden-frame gate for §4.5 step 2: the flat provider makes the whole
/// pipeline deterministic, so these tests pin down frame composition by
/// sampling pixels — same trip, same config, same bytes.
final class RecapFrameTests: XCTestCase {
    /// 1 km straight meridian route (matches CameraPathTests) rendered into a
    /// small 216×384 frame (1080×1920 ÷ 5) to keep the gate fast.
    private let route: [CameraPath.Point] = (0...10).map {
        CameraPath.Point(lat: -32.0 + Double($0) * 0.0009, lon: 115.75)
    }

    private let widthPx = 216
    private let heightPx = 384

    private func exportConfig(
        targetDurationS: Double = 6,
        fps: Int = 10,
        keyframeIntervalFrames: Int = 15
    ) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: fps, stopHoldS: 1.5, maxHoldFraction: 0.5,
            gifFps: 12, gifWidthPx: 480, frameWidthPx: widthPx, frameHeightPx: heightPx,
            cameraSpanM: 1500, keyframeIntervalFrames: keyframeIntervalFrames,
            titleCardS: 1, endCardS: 1
        )
    }

    // Style colors as 8-bit sRGB, for pixel assertions.
    private let routeRGB = RGB(red: 33, green: 115, blue: 242)
    private let headRGB = RGB(red: 255, green: 74, blue: 69)
    private let backgroundRGB = RGB(red: 237, green: 237, blue: 232)
    private let cardRGB = RGB(red: 255, green: 255, blue: 255)

    /// Card at full opacity so its pixels are exactly white regardless of the
    /// background under it.
    private var opaqueCardStyle: RecapStyle {
        var style = RecapStyle()
        style.cardColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        return style
    }

    private func makePipeline(
        stops: [CameraPath.Point] = [],
        overlaysEnabled: Bool = true,
        stopCards: [RecapFrameCompositor.StopCard] = [],
        titleCard: RecapFrameCompositor.TitleCard? = nil,
        endCard: RecapFrameCompositor.EndCard? = nil,
        config: TrackingConfig.Export
    ) throws -> (path: CameraPath, compositor: RecapFrameCompositor) {
        let path = try XCTUnwrap(CameraPath(route: route, stops: stops, config: config))
        let events = OverlayTimeline.build(holds: path.holds, config: config, photosEnabled: overlaysEnabled)
        let compositor = RecapFrameCompositor(
            path: path,
            events: events,
            stopCards: stopCards,
            titleCard: titleCard,
            endCard: endCard,
            widthPx: config.frameWidthPx,
            heightPx: config.frameHeightPx,
            style: opaqueCardStyle
        )
        return (path, compositor)
    }

    private func snapshot(centeredAt position: CameraPath.Position, config: TrackingConfig.Export) async throws -> MapSnapshot {
        try await FlatSnapshotProvider().snapshot(
            centerLat: position.lat,
            centerLon: position.lon,
            spanM: config.cameraSpanM,
            widthPx: config.frameWidthPx,
            heightPx: config.frameHeightPx
        )
    }

    // MARK: - Compositor gates

    func testMidTripFrameShowsHeadDotTraveledTrailAndUntraveledNorth() async throws {
        let config = exportConfig()
        let (path, compositor) = try makePipeline(config: config)
        // Halfway: the camera sits mid-route, trail behind it to the south.
        let time = config.targetDurationS / 2
        let background = try await snapshot(centeredAt: path.position(atTime: time), config: config)
        let frame = try compositor.render(atTime: time, background: RecapBackground(current: background))

        let centerX = widthPx / 2
        let centerY = heightPx / 2
        try assertPixel(frame, col: centerX, row: centerY, is: headRGB, "head dot rides the camera center")
        // South of the dot (larger y) is traveled; north is still bare map.
        try assertPixel(frame, col: centerX, row: centerY + 20, is: routeRGB, "traveled trail behind the head")
        try assertPixel(frame, col: centerX, row: centerY - 20, is: backgroundRGB, "route ahead not drawn yet")
        try assertPixel(frame, col: 10, row: 10, is: backgroundRGB, "off-route corner is base map")
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

    func testStopHoldShowsCardAndOverlaysOffHidesIt() async throws {
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

        // S5 photos toggle off → route-only animation, no card.
        let (_, plainCompositor) = try makePipeline(
            stops: [route[5]], overlaysEnabled: false, stopCards: [card], config: config
        )
        let plain = try plainCompositor.render(atTime: time, background: RecapBackground(current: background))
        try assertPixel(plain, col: cardX, row: cardY, is: backgroundRGB, "overlays off leaves bare map")
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

    func testCrossFadeBlendsBackgroundsAndKeepsOverlayOnRoute() async throws {
        let config = exportConfig()
        let (path, compositor) = try makePipeline(config: config)
        let time = config.targetDurationS / 2
        let dark = try await FlatSnapshotProvider(red: 0.2, green: 0.2, blue: 0.2).snapshot(
            centerLat: path.position(atTime: time).lat,
            centerLon: path.position(atTime: time).lon,
            spanM: config.cameraSpanM, widthPx: widthPx, heightPx: heightPx
        )
        let light = try await snapshot(centeredAt: path.position(atTime: time), config: config)
        let frame = try compositor.render(
            atTime: time,
            background: RecapBackground(current: light, previous: dark, blend: 0.5)
        )

        // Same projection on both sides, so the head dot still hits center...
        try assertPixel(frame, col: widthPx / 2, row: heightPx / 2, is: headRGB, "head dot survives cross-fade")
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

    func testTitleCardOpensTheVideoEvenWithPhotosOff() async throws {
        let config = exportConfig()
        let title = RecapFrameCompositor.TitleCard(title: "Perth", subtitle: "Jul 16 · 1 km")
        // photos off: stop cards gone, trip chrome stays (share hook intact).
        let (path, compositor) = try makePipeline(overlaysEnabled: false, titleCard: title, config: config)
        let background = try await snapshot(centeredAt: path.position(atTime: 0.5), config: config)
        let frame = try compositor.render(atTime: 0.5, background: RecapBackground(current: background))

        // Inside the title panel, left of the centered text.
        try assertPixel(frame, col: 30, row: 25, is: cardRGB, "title panel under the top margin")
        // After the title window the panel is gone.
        let later = try compositor.render(atTime: 1.5, background: RecapBackground(current: background))
        try assertPixel(later, col: 30, row: 25, is: backgroundRGB, "title card leaves after title_card_s")
    }

    func testEndCardShowsStatsPanelWithScannableQR() async throws {
        let config = exportConfig()
        let qr = try XCTUnwrap(RecapQRCode.image(for: "https://kamome.app/r/test", sidePx: 64))
        let endCard = RecapFrameCompositor.EndCard(
            statsLines: ["1 km · 1 stop", "6 min"],
            callToAction: "Get this route",
            qrCode: qr
        )
        let (path, compositor) = try makePipeline(endCard: endCard, config: config)
        let time = config.targetDurationS - 0.5
        let background = try await snapshot(centeredAt: path.position(atTime: time), config: config)
        let frame = try compositor.render(atTime: time, background: RecapBackground(current: background))

        // Panel fill left of the centered content.
        try assertPixel(frame, col: 30, row: heightPx / 2, is: cardRGB, "end panel centered on the frame")
        // The QR sits mid-panel: its modules must survive compositing.
        var darkPixels = 0
        for row in 160..<240 {
            for col in 70..<146 {
                let sample = try pixel(frame, col: col, row: row)
                if sample.red < 100 && sample.green < 100 && sample.blue < 100 { darkPixels += 1 }
            }
        }
        XCTAssertGreaterThan(darkPixels, 50, "QR modules should be visible in the end card")
    }

    func testQRCodeGeneratorProducesCrispModules() throws {
        let qr = try XCTUnwrap(RecapQRCode.image(for: "https://kamome.app/r/test", sidePx: 128))
        XCTAssertGreaterThanOrEqual(qr.width, 128)
        XCTAssertEqual(qr.width, qr.height, "QR must stay square")
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

// MARK: - Helpers at file scope (keeps the test class under lint's size cap)

/// Counts provider hits so the keyframe cache is provably doing its job.
private final class CountingProvider: RecapSnapshotProviding {
    private let inner = FlatSnapshotProvider()
    private(set) var requestCount = 0

    func snapshot(
        centerLat: Double, centerLon: Double, spanM: Double, widthPx: Int, heightPx: Int
    ) async throws -> MapSnapshot {
        requestCount += 1
        return try await inner.snapshot(
            centerLat: centerLat, centerLon: centerLon, spanM: spanM, widthPx: widthPx, heightPx: heightPx
        )
    }
}

private struct RGB: Equatable {
    let red: Int
    let green: Int
    let blue: Int
}

private func pixels(_ image: CGImage) throws -> (data: CFData, bytesPerRow: Int) {
    let data = try XCTUnwrap(image.dataProvider?.data)
    return (data, image.bytesPerRow)
}

private func pixel(_ image: CGImage, col: Int, row: Int) throws -> RGB {
    let (data, bytesPerRow) = try pixels(image)
    let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
    let offset = row * bytesPerRow + col * 4
    return RGB(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
}

private func assertPixel(
    _ image: CGImage,
    col: Int,
    row: Int,
    is expected: RGB,
    _ label: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    let actual = try pixel(image, col: col, row: row)
    for (component, want) in [(actual.red, expected.red), (actual.green, expected.green), (actual.blue, expected.blue)] {
        XCTAssertEqual(
            component, want, accuracy: 3,
            "\(label) at (\(col),\(row)): got \(actual), expected \(expected)", file: file, line: line
        )
    }
}

private func colorCount(_ image: CGImage, matching target: RGB) throws -> Int {
    let (data, bytesPerRow) = try pixels(image)
    let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
    var count = 0
    for row in 0..<image.height {
        for col in 0..<image.width {
            let offset = row * bytesPerRow + col * 4
            if abs(Int(bytes[offset]) - target.red) <= 3,
               abs(Int(bytes[offset + 1]) - target.green) <= 3,
               abs(Int(bytes[offset + 2]) - target.blue) <= 3 {
                count += 1
            }
        }
    }
    return count
}
