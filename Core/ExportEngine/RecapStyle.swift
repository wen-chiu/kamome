import CoreGraphics
import Foundation

/// Design constants for the recap frame (§4.5). These are visual identity,
/// not behavior tunables, so they live here rather than TrackingConfig.json
/// (spec §0 governs tunables; changing these should be a design decision in
/// code review, not a config edit). Sizes are in pixels at the 1080-wide
/// reference frame and scale linearly with frame width.
///
/// Consumed by the render-side of the narrow waist: `SpriteSubjectRenderer`
/// (the moving subject) and `RecapOverlayRenderer` (route trail, stop label,
/// photo deck, title/end chrome). The story/timeline never sees it.
public struct RecapStyle {
    // Route trail (§4.5 step 2, drawn by OverlayRenderer as `routeReveal`). The
    // trail is stroked twice: a wide, soft glow pass under a crisp core, so it
    // reads as a lit line on the dark souvenir map rather than a flat polyline.
    public var routeColor = CGColor(srgbRed: 0.13, green: 0.45, blue: 0.95, alpha: 1)
    public var routeWidthPx: CGFloat = 14
    /// Glow pass under the trail. `routeGlowWidthMultiple` is relative to
    /// `routeWidthPx`; set the alpha to 0 to disable the pass entirely.
    public var routeGlowColor = CGColor(srgbRed: 0.13, green: 0.45, blue: 0.95, alpha: 0)
    public var routeGlowWidthMultiple: CGFloat = 2.6

    // Inferred legs (PD-1): stretches Kamome could not reconstruct — straight
    // lines between photo positions. They must be legible as a *guess* at a
    // glance in the published film, so they get the opposite of the confident
    // treatment: a dashed, thinner, unlit stroke. Dashes are the one convention
    // a map reader already knows for "approximate", which is why this is a dash
    // pattern rather than, say, a second color the viewer has to be taught.
    public var routeInferredColor = CGColor(srgbRed: 0.13, green: 0.45, blue: 0.95, alpha: 0.6)
    /// Relative to `routeWidthPx` — an inferred leg reads as the lighter claim.
    public var routeInferredWidthMultiple: CGFloat = 0.65
    /// Dash on/off lengths at the 1080 reference width.
    public var routeInferredDashPx: CGFloat = 26
    public var routeInferredGapPx: CGFloat = 22

    // Atmosphere (§4.5, deferred from the §3 sign-off and landed 2026-07-25).
    // Applied by `FrameCompositor` over the finished frame, so every layer —
    // map, trail, subject, overlays — sits inside the same grade. All default to
    // "off" so the plain look is unchanged unless a theme opts in.
    /// Multiplied over the frame to tint/darken it before the vignette. Alpha 0
    /// disables. A cool, low-alpha fill is what pulls a map toward "night film".
    public var gradeColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
    /// Darkening at the frame corners, 0…1 at full strength in the corners,
    /// fading to nothing by `vignetteInnerRadius` (as a fraction of the frame's
    /// half-diagonal). 0 disables.
    public var vignetteStrength: CGFloat = 0
    public var vignetteInnerRadius: CGFloat = 0.55
    public var vignetteColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)

    // Trip chrome (title / end cards, RecapOverlayChromeDrawing). Full-bleed
    // cinematic title screens rather than panels (Chiu 2026-07-30): a dark wash
    // across the whole frame with the map receding behind it, and a centred
    // stack of mark → title → metadata.
    /// The wash pushing the map back. `centerBoost` deepens it where the text
    /// sits, so the map still reads at the edges instead of the card looking
    /// like a flat black slide.
    public var chromeScrimColor = CGColor(srgbRed: 0.02, green: 0.04, blue: 0.07, alpha: 0.55)
    public var chromeScrimCenterBoost: CGFloat = 0.32
    public var chromeTitleColor = CGColor(srgbRed: 0.93, green: 0.95, blue: 0.97, alpha: 1)
    public var chromeMetaColor = CGColor(srgbRed: 0.72, green: 0.78, blue: 0.84, alpha: 1)
    /// The warm accent the prototype uses for the mark and the closing line —
    /// the one non-teal colour in the film, so it reads as brand rather than map.
    public var chromeAccentColor = CGColor(srgbRed: 0.95, green: 0.55, blue: 0.32, alpha: 1)
    /// Side of the brand mark on the title and end cards.
    public var titleMarkSidePx: CGFloat = 132

    // Legacy panel tokens, still used by the stop label's pill.
    public var cardColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96)
    public var cardTextColor = CGColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1)
    public var cardMarginPx: CGFloat = 48
    public var cardCornerPx: CGFloat = 32
    public var cardPaddingPx: CGFloat = 28
    public var titleFontPx: CGFloat = 104
    public var subtitleFontPx: CGFloat = 40
    public var statFontPx: CGFloat = 44
    public var qrSidePx: CGFloat = 320
    /// The Kamome wordmark that stands where the QR would go while no share URL
    /// exists (PD-4). Sized to carry the end card on its own, not to imitate the
    /// footprint of the code it replaces.
    public var wordmarkFontPx: CGFloat = 84

    // The moving subject (§4.5 step 1): the bundled 8-direction car sprite over a
    // north-up map, the vehicle turning rather than the world (Chiu 2026-07-25).
    /// The sprite **canvas** side on screen at the 1080 reference. Scaling by the
    /// shared canvas rather than by each drawing's content is what keeps the car
    /// from pulsing as it turns; the car itself fills 52–74% of it, so the drawn
    /// vehicle runs roughly 200–280 px.
    public var carSpriteLengthPx: CGFloat = 380
    /// Drawn only when the sprite set fails to load. Vector, so it rotates
    /// freely. The gull is the brand mascot and reads as a light glyph over the
    /// dark souvenir map — deliberately not the car's red, so the two are never
    /// confused in a still.
    public var fallbackMarker: VehicleMarker = .seagull
    public var fallbackMarkerLengthPx: CGFloat = 170
    public var fallbackMarkerColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    public var markerColor = CGColor(srgbRed: 0.95, green: 0.27, blue: 0.28, alpha: 1)
    public var markerAccentColor = CGColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 0.92)
    public var markerOutlineColor = CGColor(srgbRed: 0.11, green: 0.13, blue: 0.19, alpha: 1)

    /// How much room the subject occupies, whichever visual is drawn — the
    /// larger of the two, so callers can reason about the vehicle's footprint
    /// without knowing which visual rendered.
    public var subjectLengthPx: CGFloat { max(carSpriteLengthPx, fallbackMarkerLengthPx) }

    // Photo deck (§5; zoom-in reveal, Chiu 2026-07-25): the card opens from
    // `min` to `max` frame width as the shot pushes in, so the map and trail
    // stay visible around it. The card opens above the stop's pin + name.
    //
    // Sized up on 2026-07-30 for photo recall — a stop's photograph is the point
    // of the beat, and at 0.30-0.50 it read as a thumbnail. `overshoot` lets the
    // bloom settle back from slightly past full size, which is what makes the
    // card arrive rather than merely appear.
    public var deckPhotoMinWidthFraction: CGFloat = 0.42
    public var deckPhotoMaxWidthFraction: CGFloat = 0.58
    public var deckPhotoAspect: CGFloat = 1.25         // portrait card (h / w)
    /// How far past `max` the opening bloom reaches before settling back.
    public var deckRevealOvershoot: CGFloat = 0.06
    public var deckMatteColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    public var deckMattePx: CGFloat = 14
    public var deckCornerPx: CGFloat = 28
    public var deckShadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35)
    public var deckDotRadiusPx: CGFloat = 7
    public var deckDotOnColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    public var deckDotOffColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4)

    // Stop label (§5 two-beat lead): the pin sits **on** the stop and the name
    // pill stands on the pin (Chiu 2026-07-26 — the car parks and disappears for
    // the stop, so nothing has to be dodged). Drawn by OverlayRenderer.
    public var labelPinColor = CGColor(srgbRed: 0.35, green: 0.85, blue: 0.95, alpha: 1)
    public var labelPinRingColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9)
    public var labelPinRadiusPx: CGFloat = 16
    public var labelPillColor = CGColor(srgbRed: 0.1, green: 0.12, blue: 0.16, alpha: 0.92)
    public var labelTextColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    public var labelDetailColor = CGColor(srgbRed: 0.7, green: 0.75, blue: 0.8, alpha: 1)
    public var labelFontPx: CGFloat = 46
    public var labelDetailFontPx: CGFloat = 32
    public var labelPillPaddingPx: CGFloat = 24
    /// Pin → name pill, and pill → card, inside the stop group.
    public var labelPinGapPx: CGFloat = 16

    public init() {}

    /// **Modern Minimal** — the overlay half of the theme whose map half is
    /// `Config/RecapThemes/modern-minimal.json` (spec §7; the ONE MVP theme).
    ///
    /// Tuned against the dark subtractive souvenir map: a glowing cyan trail
    /// instead of the flat blue polyline, a cool grade, and a soft vignette that
    /// pulls the eye to the middle of the frame where the car and the photo card
    /// live. Chrome panels go dark so a white card never punches a hole in a
    /// night-time film.
    ///
    /// This preset is what the app renders; the plain `RecapStyle()` defaults
    /// stay deliberately neutral for the deterministic golden-frame gates, which
    /// assert exact pixels and must not move when the theme is retuned.
    public static var modernMinimal: RecapStyle {
        var style = RecapStyle()
        // Glowing trail: a wide translucent pass under a bright, crisp core.
        style.routeColor = CGColor(srgbRed: 0.42, green: 0.87, blue: 0.98, alpha: 1)
        style.routeWidthPx = 17
        style.routeGlowColor = CGColor(srgbRed: 0.22, green: 0.62, blue: 0.92, alpha: 0.32)
        style.routeGlowWidthMultiple = 3.0
        // Inferred: same hue so it still reads as the journey, but unlit,
        // thinner and dashed — visibly a guess, not a road.
        style.routeInferredColor = CGColor(srgbRed: 0.42, green: 0.87, blue: 0.98, alpha: 0.55)
        // Atmosphere.
        style.gradeColor = CGColor(srgbRed: 0.05, green: 0.10, blue: 0.19, alpha: 0.16)
        style.vignetteStrength = 0.42
        style.vignetteInnerRadius = 0.52
        // Night chrome: dark panels, light type.
        style.cardColor = CGColor(srgbRed: 0.07, green: 0.09, blue: 0.13, alpha: 0.90)
        style.cardTextColor = CGColor(srgbRed: 0.97, green: 0.98, blue: 1, alpha: 1)
        return style
    }
}
