import CoreGraphics
import Foundation

/// **The shipped preset, and the colours only it uses** — split out of
/// `RecapStyle.swift` on 2026-08-28 to keep both files inside the 400-line
/// limit, the same way `RecapOverlay*Drawing` and `RecapDemoFilmAssets` already
/// are. The struct next door is the token vocabulary; this is the one theme that
/// speaks it.
public extension RecapStyle {
    // MARK: - The two trails
    //
    // One journey, two bases, and the trail cannot be the same colour on both.
    // This is legibility, measured, not preference — see `trailOnLight`.

    /// The trail over a **dark** base: the cyan tuned against the subtractive
    /// souvenir map (`Docs/decisions.md` 2026-07-22) and shipped since. Over
    /// near-black terrain it is the brightest thing in the frame.
    static let trailOnDark = CGColor(srgbRed: 0.42, green: 0.87, blue: 0.98, alpha: 1)

    /// The trail over a **light** base (Chiu, 2026-08-27).
    ///
    /// **Why it cannot stay cyan.** On Apple Maps' light base the cyan is the
    /// same colour family as the ocean, lakes, rivers and fjords the trail
    /// crosses. In the 2026-08-27 light still the north-coast leg between
    /// Sauðárkrókur and Húsavík is not distinguishable from a fjord, and the
    /// south-coast leg past Hvannadalshnúkur runs along the shoreline and
    /// disappears into the sea beside it. The dark still, same frame, same
    /// subject size, has no such problem. A warm hue is the one direction that
    /// cannot collide with water on either base.
    ///
    /// **Why this warm hue and not another.** It is `routeAccent` — the value
    /// this file already carries, whose own comment calls it "the trail's brand
    /// colour", taken from the validated web prototype's `--route`. Kamome
    /// already draws the progress dot and the stop's strap line in it, and
    /// `chromeAccentColor` puts a near-miss of it on the end card. Introducing a
    /// fourth warm value would be the "three near-misses" the accent exists to
    /// prevent.
    ///
    /// ✅ **CHOSEN by Chiu, 2026-08-29**, from the three-candidate sweep rendered
    /// on one frame (`Docs/eng-session-appearance.md` §6): this is candidate **B**,
    /// against `chromeAccentColor` `(0.95,0.55,0.32)` and a deeper
    /// `(0.96,0.42,0.15)`. Judged from
    /// `~/Kamome-films/2026-08-28-appearance/light-*`.
    static let trailOnLight = routeAccent

    /// How much weaker a dashed leg is than the solid trail it is derived from.
    ///
    /// **A provenance rule wearing a number** (PD-1, spec §0). An inferred leg is
    /// a straight guess between two photo positions, and the published film is
    /// where that has to be visible — so it is the same claim, made more weakly:
    /// same hue, this alpha, and `routeInferredWidthMultiple` of the width. The
    /// value is the one the preset has carried since 2026-07-25; what changed on
    /// 2026-08-28 is that it is now *applied* to whatever `routeColor` is rather
    /// than written out a second time beside it.
    static let routeInferredAlpha: CGFloat = 0.55

    /// The glow pass's own blue, kept at the value the preset carried until
    /// `a58942d` retired it.
    ///
    /// ⚠️ Not a decoration: `a58942d` set the alpha to 0 **on the plain default's
    /// blue** `(0.13, 0.45, 0.95)`, not on this one, so "the glow is one line
    /// away" was not quite true — raising that alpha would have restored a
    /// *different* blue than the pass Chiu once accepted on the dark map. Holding
    /// the retired colour here makes the alpha the only variable, which is what
    /// the 2026-08-28 dark A/B needs in order to answer the question it asks.
    static let retiredGlowColor = CGColor(srgbRed: 0.22, green: 0.62, blue: 0.92, alpha: 1)

    /// **Modern Minimal** — the overlay half of the theme whose map half is
    /// `Config/RecapThemes/modern-minimal.json` (spec §7; the ONE MVP theme).
    ///
    /// A cool grade and a soft vignette that pull the eye to the middle of the
    /// frame where the car and the photo card live, dark chrome so a white card
    /// never punches a hole in the film, and the trail — which is the one thing
    /// that **cannot be shared between the two bases**.
    ///
    /// **A function of the appearance, deliberately, rather than two static
    /// properties or one property reading the environment.** The preset was tuned
    /// against the dark souvenir map in 2026-07-22 and kept rendering unchanged
    /// when the 2026-08-15 substrate ADR moved films onto Apple Maps' light base;
    /// the glow defect (`a58942d`) was the visible half of that, and the trail
    /// colliding with the ocean is the half that survived it. Requiring the
    /// appearance as an argument means no caller — app, desk harness or gate —
    /// can obtain this preset without saying which base it is for, which is the
    /// property that would have caught both.
    ///
    /// The plain `RecapStyle()` defaults stay deliberately neutral for the
    /// deterministic golden-frame gates, which assert exact pixels and must not
    /// move when the theme is retuned.
    static func modernMinimal(_ appearance: RecapAppearance) -> RecapStyle {
        var style = RecapStyle()
        style.routeWidthPx = 17
        switch appearance {
        case .dark:
            style.routeColor = trailOnDark
            // **No glow, and on the dark base this is now settled too** (Chiu,
            // 2026-08-29, from the α0 / α0.32 pair at
            // `~/Kamome-films/2026-08-28-appearance/dark-glow-*`).
            //
            // The question was real rather than inherited: `a58942d` retired the
            // pass *because the base was light*, and its own message says it is
            // the right treatment again the day a dark base returns — so Chiu's
            // acceptance of "the halo is gone", judged on a light render, did not
            // carry over. Rendered on dark, the pass works exactly as designed
            // (measured: it lifts the terrain beside the trail by (8,29,29), i.e.
            // it composites *lighter* than the ground) and he chose the trail
            // without it anyway. The mechanism stays, guarded on alpha in
            // `drawRouteLeg`; `retiredGlowColor` keeps the original blue so a
            // future A/B still has alpha as its only variable.
            style.routeGlowColor = retiredGlowColor.copy(alpha: 0) ?? retiredGlowColor
            style.routeGlowWidthMultiple = 3.0
        case .light:
            style.routeColor = trailOnLight
            // No glow on a light base, and this one *is* settled: a wide
            // translucent stroke under the core composites darker than pale
            // terrain and reads as a shadow ringing the trail — measured at 3.12x
            // the core's width in the 2026-08-21 Iceland film, and judged gone by
            // Chiu on film A (`a58942d`, 2026-08-22).
            style.routeGlowColor = style.routeColor.copy(alpha: 0) ?? style.routeColor
            // ⏳ **Two tokens caught in the same water-colour trap as the trail**
            // (Chiu approved the direction 2026-08-29; the *values* are still his
            // to judge from `~/Kamome-films/2026-08-29-tokens/`).
            //
            // The stop pin takes the trail's own hue. That is not a new rule
            // being invented for light — it is the rule the dark preset has
            // always followed without saying so: `labelPinColor` `(0.35,0.85,0.95)`
            // is within 0.07 of `trailOnDark` on every channel. Left as cyan on a
            // light base it is a water-coloured dot sitting on a coastline, which
            // is exactly the collision the trail was moved out of. Dark is
            // deliberately not touched here, so the change is one appearance wide.
            style.labelPinColor = trailOnLight
            // The fallback marker's job changed on 2026-08-28, and that is why
            // this is not cosmetic. It is drawn only when the vehicle artwork
            // cannot be loaded — a failure that is intermittent, undiagnosed, and
            // (until another branch made it log) silent. During the appearance
            // renders one still in four came back with the gull instead of the
            // car, and **the wrong still survived review precisely because a
            // white gull on a light base is hard to see**. So this token is now
            // partly a diagnostic: it has to say "something went wrong" at a
            // glance.
            //
            // Hence the ink rather than the trail's orange — a warm gull would
            // sit on the warm trail it is travelling along and read as styling.
            // The value is `markerOutlineColor`'s, reused rather than invented,
            // so the film gains no new colour. Only `fill` matters: the shipped
            // `.seagull` is a single stroked arc and never reads `accent` or
            // `outline` (`RecapVehicleMarker.drawSeagull`).
            style.fallbackMarkerColor = CGColor(srgbRed: 0.11, green: 0.13, blue: 0.19, alpha: 1)
        }
        // Derived, never chosen: the dashed leg is the same claim made weaker.
        // See `routeInferredAlpha` — this is the product rule, not a colour pick.
        style.routeInferredColor = style.routeColor.copy(alpha: routeInferredAlpha) ?? style.routeColor
        // Atmosphere. Shared by both appearances **for now**: a cool wash and a
        // black vignette were tuned for a night film, and what they do to a pale
        // base is a judgement Chiu has not been given a still of. Reported rather
        // than pre-empted (`Docs/eng-session-appearance.md` §5).
        style.gradeColor = CGColor(srgbRed: 0.05, green: 0.10, blue: 0.19, alpha: 0.16)
        style.vignetteStrength = 0.42
        style.vignetteInnerRadius = 0.52
        // Night chrome: dark panels, light type. Shared for the same reason.
        style.cardColor = CGColor(srgbRed: 0.07, green: 0.09, blue: 0.13, alpha: 0.90)
        style.cardTextColor = CGColor(srgbRed: 0.97, green: 0.98, blue: 1, alpha: 1)
        return style
    }
}

public extension RecapStyle {
    /// This style with `export.end_card_style` applied. An unknown value falls
    /// back to `.full` rather than failing a render — a bad config string should
    /// cost the premium look, not the film.
    func withEndCard(_ raw: String) -> RecapStyle {
        var copy = self
        copy.endCard = RecapEndCardTreatment(rawValue: raw) ?? .full
        return copy
    }
}
