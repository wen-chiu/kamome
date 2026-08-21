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

    /// **The shipped preset draws no glow** (Chiu 2026-08-22).
    ///
    /// The rule moved rather than the code breaking: the glow was tuned for the
    /// dark souvenir map, and over the light Apple Maps base that has shipped
    /// since the 2026-08-15 substrate ADR the same translucent mid-blue
    /// composites *darker* than the terrain — a shadow ringing the trail, at
    /// 3.12x the core's width in the 2026-08-21 Iceland film.
    ///
    /// Pinned on the preset rather than left to `testRouteGlowWidensTheTrail`,
    /// because that test now supplies its own glow: with nothing asserting the
    /// preset, re-enabling it would be silent.
    func testModernMinimalDrawsNoGlowUnderTheTrail() {
        XCTAssertEqual(
            RecapStyle.modernMinimal.routeGlowColor.alpha, 0,
            "the shipped preset must not stroke a glow under the trail on a light base map"
        )
    }

    /// The glow pass widens the trail without replacing its core colour.
    ///
    /// Still exercised, and deliberately **not** read off `modernMinimal` any
    /// more: no shipped style asks for a glow today, so the mechanism has to be
    /// asked for explicitly here or it goes untested and rots (Arch.md §7.2 — a
    /// case you merely believe still works is one you have not tested). The
    /// values are the ones the preset carried until 2026-08-22, so this is the
    /// same experiment it always ran.
    func testRouteGlowWidensTheTrail() async throws {
        var plain = RecapStyle()
        plain.routeColor = RecapStyle.modernMinimal.routeColor
        plain.routeWidthPx = RecapStyle.modernMinimal.routeWidthPx

        var glowing = plain
        glowing.routeGlowColor = CGColor(srgbRed: 0.22, green: 0.62, blue: 0.92, alpha: 0.32)
        glowing.routeGlowWidthMultiple = 3.0

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
