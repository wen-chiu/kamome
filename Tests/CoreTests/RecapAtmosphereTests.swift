import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import XCTest

/// The compositor atmosphere and the Modern Minimal preset (§4.5, deferred from
/// the §3 sign-off and landed 2026-07-25). Atmosphere is applied over the
/// finished frame, so it must be **off by default** — the golden-frame gates
/// assert exact pixels and would move the moment a theme leaked into them.
final class RecapAtmosphereTests: RecapRenderTestCase {
    private func render(style: RecapStyle) async throws -> CGImage {
        let config = exportConfig()
        let timeline = try makeTimeline(makeTrip(config: config), config: config)
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(style: style, config: config),
            overlay: RecapOverlayRenderer(style: style, resolver: StubResolver { _ in nil }),
            style: style,
            widthPx: widthPx, heightPx: heightPx
        )
        return try await renderFrame(timeline, compositor, at: config.targetDurationS / 2, config: config)
    }

    func testDefaultStyleAppliesNoAtmosphere() async throws {
        let style = RecapStyle()
        XCTAssertEqual(style.gradeColor.alpha, 0, "the neutral style must not grade")
        XCTAssertEqual(style.vignetteStrength, 0, "the neutral style must not vignette")
        // A corner is still exactly the flat map fill — nothing laid over it.
        let frame = try await render(style: style)
        try assertPixel(frame, col: 4, row: 4, is: backgroundRGB, "no atmosphere over the corner")
    }

    /// The vignette has to actually darken the corners *relative to the middle*,
    /// and must not simply dim the whole frame.
    func testModernMinimalDarkensCornersMoreThanTheCentre() async throws {
        let frame = try await render(style: .modernMinimal)

        func luma(col: Int, row: Int) throws -> Double {
            let sample = try pixel(frame, col: col, row: row)
            return 0.2126 * Double(sample.red) + 0.7152 * Double(sample.green) + 0.0722 * Double(sample.blue)
        }
        // Sample map-only points: a corner, and a spot clear of the vehicle.
        let corner = try luma(col: 3, row: 3)
        let midEdge = try luma(col: widthPx / 2, row: heightPx / 4)
        XCTAssertLessThan(corner, midEdge * 0.92, "corners must fall away from the middle of the frame")
        XCTAssertGreaterThan(corner, 0, "the vignette must not crush the corner to black")
    }

    /// The glow pass widens the trail without replacing its core colour.
    func testRouteGlowWidensTheTrail() async throws {
        var plain = RecapStyle()
        plain.routeColor = RecapStyle.modernMinimal.routeColor
        plain.routeWidthPx = RecapStyle.modernMinimal.routeWidthPx

        var glowing = plain
        glowing.routeGlowColor = RecapStyle.modernMinimal.routeGlowColor
        glowing.routeGlowWidthMultiple = RecapStyle.modernMinimal.routeGlowWidthMultiple

        // Count pixels that are neither bare map nor the trail's own core: with
        // the glow enabled the trail acquires a halo of blended tones.
        func haloCount(_ image: CGImage) throws -> Int {
            var count = 0
            for row in 0..<heightPx {
                for col in 0..<widthPx {
                    let sample = try pixel(image, col: col, row: row)
                    let isMap = abs(sample.red - backgroundRGB.red) <= 3
                        && abs(sample.green - backgroundRGB.green) <= 3
                    if !isMap, sample.blue > sample.red + 20, sample.blue < 250 { count += 1 }
                }
            }
            return count
        }

        let without = try await haloCount(render(style: plain))
        let with = try await haloCount(render(style: glowing))
        XCTAssertGreaterThan(with, Int(Double(without) * 1.5), "the glow pass must broaden the trail")
    }

    func testModernMinimalUsesNightChromeSoPanelsDoNotPunchHoles() {
        let style = RecapStyle.modernMinimal
        let components = style.cardColor.components ?? []
        XCTAssertEqual(components.count, 4)
        XCTAssertLessThan(components[0], 0.2, "chrome panels must be dark, not white")
        let text = style.cardTextColor.components ?? []
        XCTAssertGreaterThan(text[0], 0.8, "chrome type must be light on the dark panel")
    }
}
