import CoreGraphics
import Foundation

/// **Here, and there** — the two marks on the ends of the flight (Chiu
/// 2026-09-04), drawn over the opening's still frame and nowhere else.
///
/// Beside the boarding pass because they answer the same question in two halves:
/// the pass says *where* in words, these say *here and there* on the picture.
/// Together they are the closeout's handover item 1 — *"the wide flight frame
/// loses the viewer"* — answered without drawing a single place name.
///
/// 🔴 **The icebox stays frozen.** What is drawn is a wordless Kamome mark, not a
/// label; `Docs/icebox.md`'s map place names are untouched and
/// `crossing_flight_max_longitude_deg` stays 70.
extension RecapOverlayRenderer {
    /// **`Landmarks/flight-end.png`, the landmark's own artwork** (Chiu
    /// 2026-09-04) — its own resource so it can be replaced without touching a
    /// vehicle sprite, and so it can never be offered as one. See
    /// `LandmarkArtwork` and `Resources/Landmarks/README.md`.
    ///
    /// 🔴 **When it does not load, this falls back to the vector
    /// `VehicleMarker.seagull` and `LandmarkArtwork` logs why.** It never draws
    /// nothing: a mark that silently disappears takes *here and there* off the
    /// frame and leaves an 8,891 km texture, which is the defect the marks exist
    /// to fix. The vector is the same bird as the end card's wordmark and is
    /// **sized and coloured at this call site, never reshaped** (`HANDOFF.md`
    /// 2026-08-29 finding 5b).
    /// 🔴 **The mark and the name fade on different clocks** (ADR 2026-09-05 (c)).
    /// The name is drawn at `opacity`, the whole overlay's; the mark at
    /// `opacity × markOpacity`, so the origin's gull can hand the point over to
    /// the departure stop's pin while `TAIWAN` stays on screen throughout.
    func drawFlightEnds(
        origin: RecapFlightEnd, destination: RecapFlightEnd, opacity: Double,
        into surface: RenderSurface
    ) {
        guard opacity > 0.001 else { return }
        let context = surface.context
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(CGFloat(opacity))
        let side = style.flightEnd.markLengthPx * surface.scale
        for end in [origin, destination] {
            let at = surface.cgPoint(lat: end.coordinate.lat, lon: end.coordinate.lon)
            if end.markOpacity > 0.001 {
                context.saveGState()
                context.setAlpha(CGFloat(opacity * end.markOpacity))
                if let artwork = LandmarkArtwork.flightEnd {
                    context.draw(artwork, in: CGRect(
                        x: at.x - side / 2, y: at.y - side / 2, width: side, height: side
                    ))
                } else {
                    VehicleMarker.seagull.draw(
                        in: context, at: at, lengthPx: side, rotationDegrees: 0,
                        colors: VehicleMarker.Palette(
                            fill: style.labelTextColor,
                            accent: style.labelTextColor,
                            outline: style.labelShadowColor
                        )
                    )
                }
                context.restoreGState()
            }
            // **The country, and nothing else** — no stop, no city, no other kind
            // of place name (ADR 2026-09-04 §3). Absent when `CountryExtent` has
            // no row: the mark is still drawn, the name is simply not claimed.
            guard let name = end.name else { continue }
            drawShadowedText(
                name,
                anchor: CGPoint(x: at.x, y: at.y - side * 0.5 - style.flightEnd.nameFontPx * surface.scale),
                fontPx: style.flightEnd.nameFontPx,
                tracking: style.flightEnd.nameFontPx * style.labelDetailTrackingEm * surface.scale,
                color: style.labelTextColor, in: surface
            )
        }
    }
}
