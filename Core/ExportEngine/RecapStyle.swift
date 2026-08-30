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
/// How the film signs off.
///
/// A **style** choice, not a branch in the renderer: the closing beat is one of
/// the clearest places a tier can differ, and the difference is entirely visual.
/// Kept as a named treatment so the swap is a value, never an `if premium`
/// scattered through the drawing code.
public enum RecapEndCardTreatment: String, Sendable {
    /// The default, and what the free tier ships: a full-bleed closing card —
    /// scrim, mark, wordmark, the trip's stats, and the call to action.
    case full
    /// A small wordmark in the corner and nothing else. The reveal still plays,
    /// so the film ends on the journey itself rather than on a panel about it.
    ///
    /// **Intended for a paid tier** (Chiu 2026-08-02). No tier system exists yet —
    /// this is the visual option existing and being swappable ahead of one, so
    /// when entitlements land they select a treatment rather than needing this
    /// built. Selected today by `export.end_card_style`.
    case minimal
}

public struct RecapStyle {
    /// Which closing treatment this style uses. See `RecapEndCardTreatment`.
    public var endCard: RecapEndCardTreatment = .full
    /// Corner mark size for the minimal ending — small enough to sign the film
    /// without competing with the route it is signing.
    public var minimalMarkSidePx: CGFloat = 56
    // Route trail (§4.5 step 2, drawn by OverlayRenderer as `routeReveal`). The
    // trail *can* be stroked twice — a wide, soft glow pass under a crisp core,
    // which reads as a lit line on a dark souvenir map rather than a flat
    // polyline. No shipped style asks for it in either appearance, and both are
    // now settled: off on light because it composites darker than pale terrain
    // and rings the trail with a shadow (Chiu 2026-08-22), and off on dark
    // because he judged the pair and preferred the trail without it (2026-08-29).
    // The pass stays for a style that asks. See `modernMinimal(_:)`.
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
    //
    // **Derived, never chosen** in the shipped preset — `modernMinimal(_:)` sets
    // it from `routeColor` at `routeInferredAlpha`. This is honest provenance, a
    // product rule (spec §0), not styling: whatever colour the solid trail takes,
    // the dashed one has to be the same claim made more weakly. Written as a
    // second literal it can drift from the trail by one edit, which is exactly
    // what an appearance-dependent trail colour makes easy.
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
    /// How much of the frame the opening title's band occupies, measured from the
    /// bottom. Everything above it is left clear for the establishing shot.
    public var titleBandHeightFraction: CGFloat = 0.27
    /// Opacity at the band's bottom edge; it fades to nothing at the top.
    public var titleBandOpacity: CGFloat = 0.9
    /// How much of the band holds full opacity before the fade begins.
    public var titleBandSolidFraction: CGFloat = 0.55
    /// Where the type sits inside the band, as a fraction of its height.
    public var titleStackCenterFraction: CGFloat = 0.46
    /// The title's side margin, as a multiple of `cardMarginPx`.
    public var titleSideMarginScale: CGFloat = 1.6
    /// The mark shrinks inside the band — branding signs the opening, it is not
    /// the subject of it.
    public var titleBandMarkScale: CGFloat = 0.55

    // Legacy panel tokens. ⚠️ **Nothing draws these** — the stop label's pill
    // they belonged to was removed on 2026-07-31 when the label was restyled to
    // the prototype's unplated `.clabel` (see `labelPinColor` below), and no
    // renderer has read them since; grep-verified 2026-08-28. They survive only
    // because two tests still assert their values, one of which
    // (`RecapRenderTestCase.opaqueCardStyle`) believes it is changing what a
    // frame looks like. Left in place rather than deleted here: removing them
    // touches four test files and belongs to its own change, not to the
    // appearance one. Recorded in `HANDOFF.md` 2026-08-28 finding 3.
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
    // The subject's on-screen size is no longer a style token: it moved to
    // `export.subject_length_px` so it can be tuned without a rebuild, and
    // `vehicles.json` may override it per subject. `RecapStyle` keeps only what
    // the *marker* fallback needs, which no manifest describes.
    /// Drawn only when the sprite set fails to load. Vector, so it rotates
    /// freely. The gull is the brand mascot and reads as a light glyph over the
    /// dark souvenir map — deliberately not the car's red, so the two are never
    /// confused in a still.
    /// A **badge** since 2026-08-29 (Chiu), not a bare bird: a disc, a ring, and
    /// the gull inside it. The reasoning is in `drawSeagullBadge` — in short, a
    /// bare gull is only as visible as the terrain under it happens to allow,
    /// and a badge carries its own contrast.
    ///
    /// `.seagull` is deliberately still here and still drawn: it is the end-card
    /// brand mark (`RecapOverlayChromeDrawing.drawMark`), and it is what the
    /// cross-region narrator would use. Pointing this token at a new case rather
    /// than restyling `.seagull` is what keeps the fault indicator and the brand
    /// mark from being one drawing with two jobs.
    public var fallbackMarker: VehicleMarker = .seagullBadge
    /// The marker's size **as a fraction of the subject it stands in for**, not
    /// as pixels of its own (Chiu 2026-08-29).
    ///
    /// It was an absolute `170` until then, and an absolute encodes a
    /// relationship at one particular subject size and afterwards stops meaning
    /// it. That is not hypothetical here: ADR 2026-08-27 moved
    /// `export.subject_length_px` 225 → 157.5 and **the stand-in became larger
    /// than the vehicle**, silently, because the two numbers sat side by side
    /// with nothing tying them together. A fraction cannot invert — at ≤ 1 the
    /// marker is at most the subject, whatever the subject becomes.
    ///
    /// Same reasoning, and deliberately the same shape, as `length_fraction` in
    /// `vehicles.json`: a mark is sized *against* the vehicle. The manifest
    /// cannot supply this one — the fallback fires precisely when the manifest
    /// could not be read.
    ///
    /// **0.60 (Chiu, 2026-08-29)**, from a 1.00 / 0.80 / 0.65 still sweep of the
    /// badge — he asked for smaller than the smallest rendered, so 0.60 was
    /// rendered and judged on its own rather than assumed to carry. At the
    /// shipped `subject_length_px` of 157.5 the badge draws at **94.5 px**.
    /// A filled disc reads heavier than the outline gull it replaced, which is
    /// why the number went down rather than staying where the bare marker sat.
    ///
    /// ⏳ **Open, deliberately:** judged from a still, and Chiu has reserved the
    /// right to revisit it from a film. Do not record this as settled.
    public var fallbackMarkerLengthFraction: CGFloat = 0.60
    /// The badge's **disc**: `#1D6FE0` (Chiu, 2026-08-29), token luminance
    /// **0.399**. One value for both appearances — the badge carries its own
    /// contrast, so no preset picks this per appearance and there is no dark
    /// variant to choose.
    ///
    /// **How much room there is, because the next person to change it will need
    /// it.** `testTheFallbackMarkerCarriesItsOwnContrast` requires this and
    /// `fallbackMarkerOnDiscColor` to straddle mid-grey and sit ≥ 0.45 apart.
    /// While the ring and gull are white, straddling binds first: **the disc must
    /// stay below 0.50**, so this value has **0.101 of headroom**.
    ///
    /// - **Deeper and more saturated is free** — going darker only widens the
    ///   separation, and there is no lower bound.
    /// - **Markedly lighter is not.** `#2E7FE8` (0.460) was the last usable step;
    ///   it was rendered at the shipped size, Chiu saw it, and he moved back here
    ///   deliberately once the wall was explained. Past 0.50 the badge has no
    ///   dark half and disappears on a pale map exactly as the white gull did.
    /// - A genuinely **light** blue is reachable only by **inverting the pair** —
    ///   light disc, dark ring and gull. The rule is symmetric and already allows
    ///   it (verified by running the guard, not by reading it), so that is the
    ///   exit rather than a test to argue with.
    public var fallbackMarkerColor = CGColor(srgbRed: 0.114, green: 0.435, blue: 0.878, alpha: 1)
    /// The badge's **ring and gull**, which are one colour: the badge has three
    /// parts but two colours, and the contrast that matters is between this and
    /// the disc rather than between either of them and the map.
    ///
    /// Fallback-specific for the reason `fallbackMarkerColor` is: it is the
    /// marker's own value, and `markerAccentColor` means "handlebars and wheels"
    /// on the line-art markers. Sharing one token would have been two roles
    /// under one name, which this file already has one casualty of.
    public var fallbackMarkerOnDiscColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    /// ⚠️ **Nothing draws this** either — the vector marker's fill comes from
    /// `fallbackMarkerColor` (`VehicleSubjectRenderer.make`'s guard), and this
    /// token has no reader anywhere in the repository; grep-verified 2026-08-28,
    /// re-checked 2026-08-29. Same treatment as the two above: reported, not
    /// removed in this change.
    public var markerColor = CGColor(srgbRed: 0.95, green: 0.27, blue: 0.28, alpha: 1)
    /// ⚠️ **Joined the list on 2026-08-29.** The badge takes its ring and gull
    /// from `fallbackMarkerOnDiscColor`, so the only markers that still read this
    /// are `.scooter` and `.bike` — and those are reachable from
    /// `RecapMarkerDeckStillsTests` and nowhere else. Reported here rather than
    /// removed, because the line-art markers are not this change's to delete.
    public var markerAccentColor = CGColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 0.92)
    public var markerOutlineColor = CGColor(srgbRed: 0.11, green: 0.13, blue: 0.19, alpha: 1)

    /// The marker's drawn length for a subject of `subjectLengthPx` — the one
    /// place the fraction is applied, so no caller can reintroduce a second
    /// number by multiplying it itself.
    public func fallbackMarkerLength(subjectLengthPx: CGFloat) -> CGFloat {
        subjectLengthPx * fallbackMarkerLengthFraction
    }

    /// How much room the subject may occupy, whichever visual is drawn.
    /// Callers pass the configured length; this answers with the larger of that
    /// and the marker, so a pixel probe can clear the subject without knowing
    /// which visual rendered.
    ///
    /// The `max` is now defence rather than arithmetic: while the fraction is
    /// ≤ 1 this is always `configured`. It stays because the day someone sets a
    /// fraction above 1 is the day a probe would otherwise start clipping the
    /// thing it is meant to clear.
    public func subjectLengthPx(configured: CGFloat) -> CGFloat {
        max(configured, fallbackMarkerLength(subjectLengthPx: configured))
    }

    // Photo deck (§5; zoom-in reveal, Chiu 2026-07-25): the card opens from
    // `min` to `max` frame width as the shot pushes in, so the map and trail
    // stay visible around it. The card opens above the stop's pin + name.
    //
    // Sized up on 2026-07-30 for photo recall — a stop's photograph is the point
    // of the beat, and at 0.30-0.50 it read as a thumbnail. `overshoot` lets the
    // bloom settle back from slightly past full size, which is what makes the
    // card arrive rather than merely appear.
    //
    // **Everything below is ported from the validated web prototype**
    // (`Docs/prototype/recap_engine.html`, `.cards` / `.card` / `.dots` /
    // `.hud`), not eyeballed from its screenshots. The prototype's 9:16 stage is
    // ~413 CSS px wide, so a prototype pixel is **×2.62** at this file's 1080
    // reference; each token below carries the CSS declaration it came from.
    public var deckPhotoMinWidthFraction: CGFloat = 0.42
    public var deckPhotoMaxWidthFraction: CGFloat = 0.58
    /// `.card { aspect-ratio: 3/4 }` — a portrait frame, so a portrait photo
    /// fills it and a landscape one is cropped to the card rather than the card
    /// stretching to the photo.
    public var deckPhotoAspect: CGFloat = 4.0 / 3.0    // portrait card (h / w)
    /// How far past `max` the opening bloom reaches before settling back.
    public var deckRevealOvershoot: CGFloat = 0.06
    public var deckMatteColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    /// `.card { border: 3px solid #fff }` — a keyline, not a passe-partout. The
    /// *frame* the card reads as comes from the drop shadow under it, not from a
    /// fat white margin.
    public var deckMattePx: CGFloat = 8
    /// `.card { border-radius: 14px }`.
    public var deckCornerPx: CGFloat = 37
    /// `.card { box-shadow: 0 20px 44px -16px rgba(0,0,0,.85) }`. CoreGraphics
    /// has no shadow *spread*, so the −16 px inset is folded into the blur.
    public var deckShadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.85)
    public var deckShadowOffsetPx: CGFloat = 52
    public var deckShadowBlurPx: CGFloat = 74

    // Secondary photos peeking out behind the hero — `.cluster.show .peekL/.peekR`
    // (`translateX(±52px) rotate(±8deg) scale(.9)` on a 204 px card). Static: the
    // deck is one hero cross-fading through the stop's photos, and these two are
    // depth, not a carousel the viewer is meant to track. The offset is a
    // *fraction of the card* so it survives the reveal's scale envelope.
    public var deckPeekOffsetFraction: CGFloat = 0.255
    public var deckPeekRotationDegrees: CGFloat = 8
    public var deckPeekScale: CGFloat = 0.9

    // Progress dots — `.dots i { width/height: 5px; gap: 5px }`, off
    // `rgba(255,255,255,.28)`, on `var(--route)` at `scale(1.35)`. Non-interactive:
    // they say "3 of 8 photos", they are not a control.
    public var deckDotRadiusPx: CGFloat = 7
    /// Centre-to-centre, as a multiple of the radius: 5 px dot + 5 px gap.
    public var deckDotSpacingMultiple: CGFloat = 4
    /// `.dots i.on { transform: scale(1.35) }`.
    public var deckDotActiveScale: CGFloat = 1.35
    /// `.dots { margin-top: 9px }` — below the stop's name, not below the card.
    public var deckDotGapPx: CGFloat = 24
    public var deckDotOnColor = RecapStyle.routeAccent
    public var deckDotOffColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.28)

    // The persistent HUD in the frame's top corners — `.hud` / `.hud .badge`
    // (`top/left/right: 22px`, `rgba(8,12,18,.55)`, `backdrop-filter: blur(8px)`,
    // `1px solid rgba(255,255,255,.09)`, `border-radius: 999px`, `padding: 6px
    // 12px`, `font-size: 12.5px`), with the distance readout opposite it
    // (`.hud .km`, its unit in `--muted` at the `<small>` size).
    //
    // **CoreGraphics has no backdrop blur.** Blurring what is already composited
    // under the pill would mean reading back the frame buffer per frame, and the
    // pill's job is legibility over an arbitrary photograph. The closest native
    // primitive is a flat fill, so the alpha is raised from .55 to .72 to buy back
    // the contrast the blur was providing.
    public var hudPillColor = CGColor(srgbRed: 0.031, green: 0.047, blue: 0.071, alpha: 0.72)
    public var hudPillBorderColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.09)
    public var hudPillBorderPx: CGFloat = 3
    public var hudFontPx: CGFloat = 33
    public var hudTextColor = CGColor(srgbRed: 0.953, green: 0.961, blue: 0.969, alpha: 1)
    /// `--muted` — the "km" unit, which must not compete with the number.
    public var hudUnitColor = CGColor(srgbRed: 0.541, green: 0.592, blue: 0.651, alpha: 1)
    public var hudPillPaddingXPx: CGFloat = 31
    public var hudPillPaddingYPx: CGFloat = 16
    /// `.hud { top: 22px; left: 22px; right: 22px }` — inset from the frame's own
    /// corners, so the row is film chrome rather than something attached to
    /// whatever happens to be on screen.
    public var hudMarginPx: CGFloat = 58

    // Stop identity (§5 two-beat lead): the pin sits **on** the stop and the
    // stop's name stands on the pin (Chiu 2026-07-26 — the car parks and
    // disappears for the stop, so nothing has to be dodged). Drawn by
    // OverlayRenderer, identically in both beats, so beat 1's label and beat 2's
    // caption cross-fade in place instead of jumping.
    //
    // Restyled 2026-07-31 to the prototype's `.clabel`: **no pill**. The name is
    // set as free type over the map with a soft drop shadow
    // (`text-shadow: 0 2px 12px rgba(0,0,0,.6)`), which is what makes it read as
    // a film title rather than a map annotation — a rounded plate behind it
    // reads as UI chrome no matter how big the type gets. The secondary line
    // takes the warm route accent, uppercase and letter-spaced.
    public var labelPinColor = CGColor(srgbRed: 0.35, green: 0.85, blue: 0.95, alpha: 1)
    public var labelPinRingColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9)
    public var labelPinRadiusPx: CGFloat = 16
    public var labelTextColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    /// `.clabel span` — the uppercase Latin strap under the name. Warm accent
    /// rather than grey: the name is the headline, this is the coloured strap,
    /// and the two never compete.
    public var labelDetailColor = RecapStyle.routeAccent
    /// `.clabel b` — the prototype sets this at 20 px on its ~413 px stage (≈52 px
    /// here). Kamome runs it larger: the film is watched on a phone at arm's
    /// length, and the place name is the one word a viewer should still have
    /// after the stop is gone.
    public var labelFontPx: CGFloat = 76
    /// `.clabel span { font-size: 11px }` — the prototype's 20:11 ratio held
    /// against the larger headline above.
    public var labelDetailFontPx: CGFloat = 42
    /// `.clabel span { letter-spacing: .16em }`, as a fraction of the font size.
    public var labelDetailTrackingEm: CGFloat = 0.16
    /// `.clabel b { letter-spacing: -.01em }`.
    public var labelTrackingEm: CGFloat = -0.01
    /// `.clabel span { margin-top: 4px }`.
    public var labelDetailGapPx: CGFloat = 11
    /// `text-shadow: 0 2px 12px rgba(0,0,0,.6)` — what keeps unplated type legible
    /// over a bright photograph or a pale glacier.
    public var labelShadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.6)
    public var labelShadowOffsetPx: CGFloat = 5
    public var labelShadowBlurPx: CGFloat = 31
    /// Pin → name, and name group → card, inside the stop group.
    public var labelPinGapPx: CGFloat = 16

    /// `--route: #FF8A5B` — the prototype's single warm accent, shared by the
    /// trail's brand colour, the active progress dot and the stop's strap line,
    /// so the film has one accent rather than three near-misses.
    public static let routeAccent = CGColor(srgbRed: 1, green: 0.541, blue: 0.357, alpha: 1)

    public init() {}
}
