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
    /// A patch that is inside the closing card at any frame size — **fractions,
    /// never reference pixels.** The golden frame is 216 × 384, so a band written
    /// as ±200 px of the centre indexes past both edges and takes the process
    /// with it.
    private static func cardRows(_ heightPx: Int) -> Range<Int> {
        (heightPx * 45 / 100)..<(heightPx * 55 / 100)
    }

    private static func cardCols(_ widthPx: Int) -> Range<Int> {
        (widthPx * 35 / 100)..<(widthPx * 65 / 100)
    }

    /// Mean luminance over the frame — how a wash is detected without pinning any
    /// particular pixel.
    private func meanLuminance(_ image: CGImage) throws -> Double {
        try meanLuminance(image, rows: 0..<heightPx, cols: 0..<widthPx)
    }

    /// Mean luminance over one band of the frame. The closing card no longer
    /// covers the frame (ADR 2026-09-05 (c)), so "is the card there?" and "can the map
    /// still be seen?" are questions about two different regions.
    private func meanLuminance(_ image: CGImage, rows: Range<Int>, cols: Range<Int>) throws -> Double {
        var total = 0.0
        var samples = 0.0
        for row in stride(from: rows.lowerBound, to: rows.upperBound, by: 4) {
            for col in stride(from: cols.lowerBound, to: cols.upperBound, by: 4) {
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
        // ...but the end card still closes the video. Measured **at the centre**,
        // where the card is: it stopped being full-bleed on 2026-09-05 and a
        // whole-frame mean would now pass on a card half this size.
        let ending = try await renderFrame(timeline, compositor, at: config.targetDurationS - 0.5, config: config)
        let mid = try await renderFrame(timeline, compositor, at: config.targetDurationS / 2, config: config)
        XCTAssertLessThan(
            try meanLuminance(ending, rows: Self.cardRows(heightPx), cols: Self.cardCols(widthPx)),
            try meanLuminance(mid, rows: Self.cardRows(heightPx), cols: Self.cardCols(widthPx)) - 10,
            "end card survives photos off"
        )
    }

    /// 🔴 **The closing card dims the map; it does not hide it** (Chiu 2026-09-05,
    /// ADR 2026-09-05 (d)).
    ///
    /// Three grounds have been tried under this stack — a full-frame scrim, a card
    /// over the map, and now a slight dim with the summary floating on it. What
    /// every version has owed is the same thing: the reveal spends its last
    /// seconds opening the frame onto the whole journey, and the ending must not
    /// paint over it. So this bounds the wash from **both** sides: there is one,
    /// and it is nowhere near the scrim's.
    ///
    /// ⚠️ **The control is the same frame with `.minimal`, not an earlier frame.**
    /// Comparing against mid-film measures the camera as much as the chrome — the
    /// end reveal is a different shot — and that comparison once failed by 9
    /// luminance points on chrome that never touched the band.
    ///
    /// ⚠️ **What this cannot see:** the golden harness renders a *flat* base, so
    /// "the trail, the coastline and the stop pins stay legible" is not gated
    /// here — it is judged on a render, in both appearances, and the dim is a
    /// per-appearance token precisely because one value cannot serve both.
    func testTheClosingCardDimsTheMapWithoutHidingIt() async throws {
        let config = exportConfig()
        let timeline = try makeTimeline(makeTrip(stops: [StopSpec(routeIndex: 5)], config: config), config: config)
        let at = config.targetDurationS - 0.5
        var bare = opaqueCardStyle
        bare.endCard = .minimal

        let dimmed = try await renderFrame(timeline, makeCompositor(timeline), at: at, config: config)
        let mapOnly = try await renderFrame(
            timeline, makeCompositor(timeline, style: bare), at: at, config: config
        )

        // A band clear of the centred stack, so this measures the wash and not the
        // type standing on it.
        let band = 0..<(heightPx / 8)
        let withCard = try meanLuminance(dimmed, rows: band, cols: 0..<widthPx)
        let without = try meanLuminance(mapOnly, rows: band, cols: 0..<widthPx)

        XCTAssertLessThan(withCard, without - 5, "there must be a dim, or the type cannot read")
        // The scrim this replaced was alpha 0.55 with a 0.32 centre boost, which
        // lands under half the base's luminance. Anything at or below that is the
        // ground Chiu rejected twice.
        XCTAssertGreaterThan(
            withCard, without * 0.6,
            "the map is dimmed to let type read, not pushed back — this is scrim territory"
        )
    }

    /// Ink over the **whole frame**: pixels that differ markedly from the dimmed
    /// ground, measured against the frame's own top-left corner so no threshold is
    /// hard-coded against a wash that has now changed three times.
    ///
    /// ⚠️ **Whole-frame, and it did not used to be.** This sampled a box at the
    /// centre, which worked while the closing card was a scrim with the mark in
    /// the middle of it. The card now dims the map and puts the mark at the top of
    /// a centred stack (ADR 2026-09-05 (d)), so a centre box measures the trip's
    /// name instead. The two frames compared here are the same film at the same
    /// instant and differ **only** in mark versus QR, so counting all of it still
    /// isolates exactly that.
    private func markInk(_ frame: CGImage) throws -> Int {
        let ground = try pixel(frame, col: 2, row: 2)
        var lit = 0
        for row in stride(from: 0, to: heightPx, by: 2) {
            for col in stride(from: 0, to: widthPx, by: 2) {
                let sample = try pixel(frame, col: col, row: row)
                let delta = max(
                    abs(Int(sample.red) - Int(ground.red)),
                    max(abs(Int(sample.green) - Int(ground.green)), abs(Int(sample.blue) - Int(ground.blue)))
                )
                if delta > 30 { lit += 1 }
            }
        }
        return lit
    }

    private func endFrame(shareURL: String?) async throws -> CGImage {
        let config = exportConfig()
        let timeline = try makeTimeline(
            makeTrip(endCardFigures: [
                RecapEndCardFigure(value: "1", label: "KM"),
                RecapEndCardFigure(value: "1", label: "DAY"),
                RecapEndCardFigure(value: "1", label: "STOP")
            ], shareURL: shareURL, config: config), config: config
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
