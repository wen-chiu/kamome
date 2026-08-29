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
        let frame = try await render(style: .modernMinimal(.dark))

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
    ///
    /// **Both appearances, and each was decided separately.** On light: judged
    /// gone by Chiu on film A (2026-08-22). On dark: the acceptance did *not*
    /// carry over — the glow was designed for a dark base — so it was rendered as
    /// an α0/α0.32 pair on 2026-08-29 and he chose the trail without it. The
    /// mechanism is intact and one alpha away in either appearance, which is
    /// exactly why this holds the rule in both: a return must never be silent.
    func testModernMinimalDrawsNoGlowUnderTheTrail() {
        for appearance in RecapAppearance.allCases {
            XCTAssertEqual(
                RecapStyle.modernMinimal(appearance).routeGlowColor.alpha, 0,
                "the shipped \(appearance) preset must not stroke a glow under the trail"
            )
        }
    }

    /// **A dashed leg is the trail's own claim, made weaker** — in every
    /// appearance (PD-1, spec §0 honest provenance).
    ///
    /// This is a product rule, not styling: an inferred leg is a straight guess
    /// between two photo positions, and the published film is where that has to
    /// be visible. It is asserted **structurally** rather than as two colour
    /// literals because the trail colour is now appearance-dependent, and the
    /// failure this guards is precisely a trail that changes while the dashes it
    /// derives from stay behind — leaving a film that draws a guess in the colour
    /// of a road it never proved.
    func testInferredLegsStayDerivedFromTheTrailInEveryAppearance() throws {
        for appearance in RecapAppearance.allCases {
            let style = RecapStyle.modernMinimal(appearance)
            let trail = try XCTUnwrap(style.routeColor.components)
            let dashed = try XCTUnwrap(style.routeInferredColor.components)
            XCTAssertEqual(
                Array(dashed.prefix(3)), Array(trail.prefix(3)),
                "\(appearance): the dashed leg must be the trail's own hue, not a second colour"
            )
            XCTAssertLessThan(
                style.routeInferredColor.alpha, style.routeColor.alpha,
                "\(appearance): the dashed leg must read as the weaker claim"
            )
            XCTAssertLessThan(
                style.routeInferredWidthMultiple, 1,
                "\(appearance): the dashed leg must be thinner than the road it is not"
            )
            XCTAssertGreaterThan(
                style.routeInferredDashPx, 0,
                "\(appearance): an inferred leg must actually be dashed"
            )
        }
    }

    /// **The light base's trail must not be in the water's colour family.**
    ///
    /// The *measured* reason for the 2026-08-27 decision, held as a rule rather
    /// than as a value so retuning the orange cannot walk it back to cyan. On
    /// Apple Maps' light base the ocean, lakes, rivers and fjords are blue, and a
    /// blue-dominant trail crossing them is not distinguishable from them — the
    /// north-coast leg between Sauðárkrókur and Húsavík in the 2026-08-27 light
    /// still reads as a fjord.
    ///
    /// "Not blue-dominant" is the cheapest test of that which does not pin a
    /// colour Chiu has yet to choose: blue must not be the strongest channel, and
    /// red must lead by a real margin rather than a rounding error.
    func testTheLightTrailIsNotInTheBaseMapsWaterColours() throws {
        let components = try XCTUnwrap(RecapStyle.modernMinimal(.light).routeColor.components)
        let (red, green, blue) = (components[0], components[1], components[2])
        XCTAssertGreaterThan(
            red, blue + 0.2,
            "a light-base trail must be warm — blue is the base map's water, not Kamome's journey"
        )
        XCTAssertGreaterThan(red, green, "the warm hue must lead on red")
    }

    /// **The stop pin travels with the trail's hue** (2026-08-29).
    ///
    /// Not a rule invented for light — the rule the dark preset had always
    /// followed without saying so: `labelPinColor` `(0.35,0.85,0.95)` is within
    /// 0.07 of `trailOnDark` on every channel. Saying it out loud is what stops a
    /// cyan pin being left on a light base, where it is a water-coloured dot on a
    /// coastline: the same collision the trail itself was moved out of, on a
    /// token nobody had looked at.
    ///
    /// Held as *hue family* rather than as equality, because the dark pin is
    /// deliberately a shade off its trail and equality would demand a change to a
    /// value nobody asked to move.
    func testTheStopPinTravelsWithTheTrailsHue() throws {
        for appearance in RecapAppearance.allCases {
            let style = RecapStyle.modernMinimal(appearance)
            let trail = try XCTUnwrap(style.routeColor.components)
            let pin = try XCTUnwrap(style.labelPinColor.components)
            let dominant = { (rgb: [CGFloat]) in rgb.prefix(3).enumerated().max { $0.element < $1.element }?.offset }
            XCTAssertEqual(
                dominant(Array(pin)), dominant(Array(trail)),
                "\(appearance): the stop pin must sit in the trail's colour family, not the base map's"
            )
        }
    }

    /// **The fallback marker must be noticed when it appears at all** — restated
    /// 2026-08-29, because the marker became a badge and the old assertion
    /// measured a relationship the badge no longer has.
    ///
    /// It is drawn only when the vehicle artwork cannot be loaded — an
    /// intermittent, undiagnosed failure. On 2026-08-28 it fired by itself in one
    /// review render of four, and **the wrong still survived review because a
    /// white gull on a light base is hard to see.** That is the rule, and it has
    /// not changed. What changed is how the marker satisfies it.
    ///
    /// **Was:** one colour, the gull's fill, against an *assumed* base — dark on
    /// light, light on dark. That rule was sound for a thin stroked bird whose
    /// only defence was differing from whatever it flew over. It also could not
    /// be satisfied in blue: every value dark enough to clear the ceiling was too
    /// dark for its hue to register (measured 2026-08-29 — the navy sweep).
    ///
    /// **Is:** the badge carries its own contrast, so the pair that must hold
    /// apart is the **disc and what is drawn on it**, and the base map stops
    /// being a term. Two conditions, and both are the rule rather than the
    /// value:
    ///
    /// 1. they straddle mid-grey, so whichever side the terrain falls on, one of
    ///    the two is on the other side of it;
    /// 2. they are far apart — wider than the **0.30** the old thresholds implied
    ///    between a compliant dark value and a compliant light one, which is the
    ///    anchor for this number rather than a fresh judgement.
    ///
    /// Asserted for **both** appearances, deliberately: whether one badge serves
    /// both is Chiu's open question, and this holds either answer to the same bar.
    func testTheFallbackMarkerCarriesItsOwnContrast() throws {
        func luminance(_ color: CGColor) throws -> CGFloat {
            let rgb = try XCTUnwrap(color.components)
            return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
        }
        let midGrey: CGFloat = 0.5
        let minimumSeparation: CGFloat = 0.45
        for appearance in [RecapAppearance.light, .dark] {
            let style = RecapStyle.modernMinimal(appearance)
            let disc = try luminance(style.fallbackMarkerColor)
            let onDisc = try luminance(style.fallbackMarkerOnDiscColor)
            XCTAssertGreaterThan(
                abs(disc - onDisc), minimumSeparation,
                "\(appearance): the ring and gull must read against the disc — \(disc) vs \(onDisc)"
            )
            XCTAssertLessThan(
                min(disc, onDisc), midGrey,
                "\(appearance): one part of the badge must be dark enough to read on a pale map"
            )
            XCTAssertGreaterThan(
                max(disc, onDisc), midGrey,
                "\(appearance): one part of the badge must be light enough to read on a dark map"
            )
        }
    }

    /// The dark base keeps the cyan it was tuned for, and it is *not* the same
    /// trail the light base draws. One value, two films — the whole point of
    /// `modernMinimal(_:)` being a function.
    func testTheTwoAppearancesDoNotShareATrail() throws {
        let dark = try XCTUnwrap(RecapStyle.modernMinimal(.dark).routeColor.components)
        let light = try XCTUnwrap(RecapStyle.modernMinimal(.light).routeColor.components)
        XCTAssertNotEqual(
            Array(dark.prefix(3)), Array(light.prefix(3)),
            "the trail that reads on near-black is the one that vanishes into a light map's sea"
        )
        XCTAssertGreaterThan(dark[2], dark[0], "the dark base keeps the cool trail it was tuned for")
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
        plain.routeColor = RecapStyle.modernMinimal(.dark).routeColor
        plain.routeWidthPx = RecapStyle.modernMinimal(.dark).routeWidthPx

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

    /// ⚠️ Asserts tokens **no renderer reads** — `cardColor` and `cardTextColor`
    /// lost their consumer when the stop label's pill was removed on 2026-07-31
    /// (`HANDOFF.md` 2026-08-28 finding 3). Kept and pinned to `.dark` here
    /// rather than deleted, because deleting it is a separate change; what it
    /// asserts today is the *intent* of the token, not the look of a frame.
    func testModernMinimalUsesNightChromeSoPanelsDoNotPunchHoles() {
        let style = RecapStyle.modernMinimal(.dark)
        let components = style.cardColor.components ?? []
        XCTAssertEqual(components.count, 4)
        XCTAssertLessThan(components[0], 0.2, "chrome panels must be dark, not white")
        let text = style.cardTextColor.components ?? []
        XCTAssertGreaterThan(text[0], 0.8, "chrome type must be light on the dark panel")
    }
}
