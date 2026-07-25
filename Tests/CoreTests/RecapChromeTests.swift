import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// §4.5 step 4 chrome gates on the render-layers pipeline: the title/end chrome
/// (drawn by `RecapOverlayRenderer`, emitted by `LinearTimeline`) and the QR
/// share hook, under the signed-off toggle contract (decisions.md 2026-07-18
/// recap-chrome). Chrome is independent of photos — a photoless (route-only)
/// trip still opens with the title and closes with the end card + share QR.
final class RecapChromeTests: RecapRenderTestCase {
    func testTitleCardOpensTheVideoEvenWithPhotosOff() async throws {
        let config = exportConfig()
        // Route-only trip (a photoless stop): the title chrome still opens it.
        let timeline = try makeTimeline(
            makeTrip(stops: [StopSpec(routeIndex: 5)], title: "Perth", subtitle: "Jul 16 · 1 km", config: config),
            config: config
        )
        let compositor = makeCompositor(timeline)

        // Inside the title panel, under the top margin, left of the centered text.
        let frame = try await renderFrame(timeline, compositor, at: 0.5, config: config)
        try assertPixel(frame, col: 30, row: 25, is: cardRGB, "title panel under the top margin")
        // After the title window the panel is gone.
        let later = try await renderFrame(timeline, compositor, at: 1.5, config: config)
        try assertPixel(later, col: 30, row: 25, is: backgroundRGB, "title card leaves after title_card_s")
    }

    /// Locks the signed-off toggle contract (decisions.md 2026-07-18, Chiu):
    /// a route-only trip drops the stop deck/label but keeps the end card and
    /// its share hook. A fully chrome-free export would be a separate explicit
    /// option, never this path.
    func testPhotosOffKeepsEndCardShareHook() async throws {
        let config = exportConfig()
        let timeline = try makeTimeline(makeTrip(stops: [StopSpec(routeIndex: 5)], config: config), config: config)
        let compositor = makeCompositor(timeline)

        // No stop deck anywhere across the route-only trip...
        for time in stride(from: 0.0, through: timeline.durationS, by: 0.25) {
            XCTAssertNil(activePhotoDeck(timeline.overlayContents(atTime: time)), "no deck with photos off at t=\(time)")
        }
        // ...but the end card still closes the video.
        let endTime = config.targetDurationS - 0.5
        let endFrame = try await renderFrame(timeline, compositor, at: endTime, config: config)
        try assertPixel(endFrame, col: 30, row: heightPx / 2, is: cardRGB, "end card survives photos off")
    }

    func testEndCardShowsStatsPanelWithScannableQR() async throws {
        let config = exportConfig()
        let timeline = try makeTimeline(
            makeTrip(statsLines: ["1 km · 1 stop", "6 min"], config: config), config: config
        )
        let compositor = makeCompositor(timeline)
        let time = config.targetDurationS - 0.5
        let frame = try await renderFrame(timeline, compositor, at: time, config: config)

        // Panel fill left of the centered content.
        try assertPixel(frame, col: 30, row: heightPx / 2, is: cardRGB, "end panel centered on the frame")
        // The QR sits mid-panel: its modules must survive compositing. The panel
        // is otherwise white, so any dark pixels are QR modules.
        var darkPixels = 0
        for row in 150..<235 {
            for col in 76..<140 {
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
}
