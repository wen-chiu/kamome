import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// §4.5 step 4 chrome gates: the opening title and the closing card, under the
/// signed-off toggle contract (decisions.md 2026-07-18 recap-chrome). Chrome is
/// independent of photos — a photoless (route-only) trip still opens with the
/// title and closes with the end card.
///
/// Both are **full-bleed title screens** since 2026-07-30 (Chiu, matching the
/// prototype): a dark wash over the whole frame with the map receding behind it,
/// rather than a white plate against one edge. So these assert the wash and the
/// content in it, not a panel at a fixed corner.
final class RecapChromeTests: RecapRenderTestCase {
    /// Mean luminance over the frame — how the full-bleed wash is detected
    /// without pinning any particular pixel.
    private func meanLuminance(_ image: CGImage) throws -> Double {
        var total = 0.0
        var samples = 0.0
        for row in stride(from: 0, to: heightPx, by: 4) {
            for col in stride(from: 0, to: widthPx, by: 4) {
                let sample = try pixel(image, col: col, row: row)
                total += Double(sample.red + sample.green + sample.blue) / 3
                samples += 1
            }
        }
        return total / samples
    }

    func testTitleCardOpensTheVideoEvenWithPhotosOff() async throws {
        let config = exportConfig()
        // Route-only trip (a photoless stop): the title chrome still opens it.
        let timeline = try makeTimeline(
            makeTrip(stops: [StopSpec(routeIndex: 5)], title: "Perth", subtitle: "Jul 16 · 1 km", config: config),
            config: config
        )
        let compositor = makeCompositor(timeline)

        let opening = try await renderFrame(timeline, compositor, at: 0.5, config: config)
        let later = try await renderFrame(timeline, compositor, at: 1.5, config: config)
        XCTAssertLessThan(
            try meanLuminance(opening), try meanLuminance(later) - 10,
            "the title card must wash the whole frame down, not sit in a corner"
        )
    }

    /// Locks the signed-off toggle contract (decisions.md 2026-07-18, Chiu):
    /// a route-only trip drops the stop deck/label but keeps the end card.
    func testPhotosOffKeepsEndCard() async throws {
        let config = exportConfig()
        let timeline = try makeTimeline(makeTrip(stops: [StopSpec(routeIndex: 5)], config: config), config: config)
        let compositor = makeCompositor(timeline)

        // No stop deck anywhere across the route-only trip...
        for time in stride(from: 0.0, through: timeline.durationS, by: 0.25) {
            XCTAssertNil(activePhotoDeck(timeline.overlayContents(atTime: time)), "no deck with photos off at t=\(time)")
        }
        // ...but the end card still closes the video.
        let ending = try await renderFrame(timeline, compositor, at: config.targetDurationS - 0.5, config: config)
        let mid = try await renderFrame(timeline, compositor, at: config.targetDurationS / 2, config: config)
        XCTAssertLessThan(
            try meanLuminance(ending), try meanLuminance(mid) - 10, "end card survives photos off"
        )
    }

    /// Ink inside the mark area at the centre of the closing stack — QR modules
    /// or the brand mark, depending on which the film is carrying.
    private func markInk(_ frame: CGImage) throws -> Int {
        var lit = 0
        for row in (heightPx / 2 - 60)..<(heightPx / 2 + 60) {
            for col in (widthPx / 2 - 40)..<(widthPx / 2 + 40) {
                let sample = try pixel(frame, col: col, row: row)
                // Anything markedly brighter than the wash it sits on.
                if sample.red > 120 || sample.green > 120 || sample.blue > 120 { lit += 1 }
            }
        }
        return lit
    }

    private func endFrame(shareURL: String?) async throws -> CGImage {
        let config = exportConfig()
        let timeline = try makeTimeline(
            makeTrip(statsLines: ["1 km · 1 stop", "6 min"], shareURL: shareURL, config: config), config: config
        )
        return try await renderFrame(
            timeline, makeCompositor(timeline), at: config.targetDurationS - 0.5, config: config
        )
    }

    /// PD-4: the MVP film closes on the Kamome mark and wordmark, not on a QR
    /// encoding `kamome://route/<id>` — a code that resolves to nothing invites
    /// the one interaction the film cannot honor.
    func testEndCardShowsTheMarkNotAQRWhenThereIsNoShareURL() async throws {
        let wordmark = try await endFrame(shareURL: nil)
        let qr = try await endFrame(shareURL: "kamome://route/test")

        XCTAssertGreaterThan(try markInk(wordmark), 0, "the brand mark must print")
        // A QR fills its square densely; a drawn mark is mostly negative space.
        XCTAssertLessThan(
            try markInk(wordmark), try markInk(qr),
            "a mark must not be as dense as a scannable code"
        )
    }

    /// The QR capability is intact and returns the day a real share URL exists
    /// (spec P6/P7) — only the MVP payload was suppressed, not the machinery.
    func testQRStillRendersWhenAShareURLIsSupplied() async throws {
        let frame = try await endFrame(shareURL: "https://kamome.app/r/test")
        XCTAssertGreaterThan(try markInk(frame), 50)
    }

    func testQRCodeGeneratorProducesCrispModules() throws {
        let qr = try XCTUnwrap(RecapQRCode.image(for: "https://kamome.app/r/test", sidePx: 128))
        XCTAssertGreaterThanOrEqual(qr.width, 128)
        XCTAssertEqual(qr.width, qr.height, "QR must stay square")
    }
}
