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
    // Route trail (§4.5 step 2, drawn by OverlayRenderer as `routeReveal`).
    public var routeColor = CGColor(srgbRed: 0.13, green: 0.45, blue: 0.95, alpha: 1)
    public var routeWidthPx: CGFloat = 14

    // Trip chrome panels (title / end cards, RecapOverlayChromeDrawing).
    public var cardColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96)
    public var cardTextColor = CGColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1)
    public var cardMarginPx: CGFloat = 48
    public var cardCornerPx: CGFloat = 32
    public var cardPaddingPx: CGFloat = 28
    public var titleFontPx: CGFloat = 72
    public var subtitleFontPx: CGFloat = 40
    public var statFontPx: CGFloat = 44
    public var qrSidePx: CGFloat = 320

    // The moving subject (§4.5 step 1): the bundled 8-direction car sprite over a
    // north-up map, the vehicle turning rather than the world (Chiu 2026-07-25).
    /// Longest on-screen side of the car sprite at the 1080 reference. The eight
    /// drawings share one square canvas, so the car keeps a constant size as it
    /// turns; the canvas is larger than the car, hence the generous value.
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
    /// larger of the two, so the floating stop label clears the car *and* the
    /// fallback marker without the overlay needing to know which one rendered.
    public var subjectLengthPx: CGFloat { max(carSpriteLengthPx, fallbackMarkerLengthPx) }

    // Photo deck (§5; zoom-in reveal, Chiu 2026-07-25): the card opens from
    // `min` to `max` frame width as the shot pushes in, so the map and trail
    // stay visible around it. The stop's pin + name ride under the card.
    public var deckPhotoMinWidthFraction: CGFloat = 0.30
    public var deckPhotoMaxWidthFraction: CGFloat = 0.50
    public var deckPhotoAspect: CGFloat = 1.25         // portrait card (h / w)
    /// Card bottom → the pin + name group under it.
    public var deckLabelGapPx: CGFloat = 40
    public var deckMatteColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    public var deckMattePx: CGFloat = 14
    public var deckCornerPx: CGFloat = 28
    public var deckShadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35)
    public var deckDotRadiusPx: CGFloat = 7
    public var deckDotOnColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    public var deckDotOffColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4)

    // Stop label (§5 two-beat lead): a pin at the stop + a name pill that floats
    // clear above the vehicle, so neither overlaps (Chiu 2026-07-25). Drawn by
    // OverlayRenderer.
    public var labelPinColor = CGColor(srgbRed: 0.35, green: 0.85, blue: 0.95, alpha: 1)
    public var labelPinRingColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9)
    public var labelPinRadiusPx: CGFloat = 16
    public var labelPillColor = CGColor(srgbRed: 0.1, green: 0.12, blue: 0.16, alpha: 0.92)
    public var labelTextColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    public var labelDetailColor = CGColor(srgbRed: 0.7, green: 0.75, blue: 0.8, alpha: 1)
    public var labelFontPx: CGFloat = 46
    public var labelDetailFontPx: CGFloat = 32
    public var labelPillPaddingPx: CGFloat = 24
    /// Clear air between the top of the vehicle and the bottom of the floating
    /// pin + name group, at the 1080 reference (the renderer adds the vehicle's
    /// own half-length on top, so neither element ever prints over the car).
    public var labelVehicleClearancePx: CGFloat = 50
    /// Pin → name pill gap inside the floating group.
    public var labelPinGapPx: CGFloat = 16

    public init() {}
}
