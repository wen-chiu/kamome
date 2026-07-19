import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// §4.5 step 4 chrome gates: title/end cards and the QR share hook, under
/// the signed-off toggle contract (decisions.md 2026-07-18 recap-chrome).
final class RecapChromeTests: RecapRenderTestCase {
    func testTitleCardOpensTheVideoEvenWithPhotosOff() async throws {
        let config = exportConfig()
        let title = RecapFrameCompositor.TitleCard(title: "Perth", subtitle: "Jul 16 · 1 km")
        // photos off: stop cards gone, trip chrome stays (share hook intact).
        let (path, compositor) = try makePipeline(photosEnabled: false, titleCard: title, config: config)
        let background = try await snapshot(centeredAt: path.position(atTime: 0.5), config: config)
        let frame = try compositor.render(atTime: 0.5, background: RecapBackground(current: background))

        // Inside the title panel, left of the centered text.
        try assertPixel(frame, col: 30, row: 25, is: cardRGB, "title panel under the top margin")
        // After the title window the panel is gone.
        let later = try compositor.render(atTime: 1.5, background: RecapBackground(current: background))
        try assertPixel(later, col: 30, row: 25, is: backgroundRGB, "title card leaves after title_card_s")
    }

    /// Locks the signed-off toggle contract (decisions.md 2026-07-18, Chiu):
    /// photosEnabled removes stop cards ONLY — the end card and its share
    /// hook must survive a route-only export. A fully chrome-free export
    /// would be a separate explicit option, never this toggle.
    func testPhotosOffKeepsEndCardShareHook() async throws {
        let config = exportConfig()
        let endCard = RecapFrameCompositor.EndCard(
            statsLines: ["1 km · 1 stop"],
            callToAction: "Get this route",
            qrCode: RecapQRCode.image(for: "https://kamome.app/r/test", sidePx: 64)
        )
        let stopCard = RecapFrameCompositor.StopCard(name: "Stop", dayLabel: "Day 1")
        let (path, compositor) = try makePipeline(
            stops: [route[5]], photosEnabled: false, stopCards: [stopCard], endCard: endCard, config: config
        )

        // No stop card during what would have been the hold...
        let hold = try XCTUnwrap(path.holds.first)
        let holdTime = (hold.startS + hold.endS) / 2
        let holdBackground = try await snapshot(centeredAt: path.position(atTime: holdTime), config: config)
        let holdFrame = try compositor.render(atTime: holdTime, background: RecapBackground(current: holdBackground))
        try assertPixel(holdFrame, col: widthPx - 25, row: heightPx - 40, is: backgroundRGB, "no stop card with photos off")

        // ...but the end card still closes the video.
        let endTime = config.targetDurationS - 0.5
        let endBackground = try await snapshot(centeredAt: path.position(atTime: endTime), config: config)
        let endFrame = try compositor.render(atTime: endTime, background: RecapBackground(current: endBackground))
        try assertPixel(endFrame, col: 30, row: heightPx / 2, is: cardRGB, "end card survives photos off")
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
    }}
