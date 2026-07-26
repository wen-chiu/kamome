import CoreGraphics
import Foundation

/// The traveled trail, split out of `RecapOverlayRenderer` to keep both files
/// readable — and because this is where the film's honesty is drawn (PD-1).
extension RecapOverlayRenderer {
    // MARK: - Route reveal (the traveled trail, leg by leg)

    /// One revealed leg, stroked for what it actually is (PD-1).
    ///
    /// A confident leg — recorded GPS, or geometry snapped to the real road
    /// network — is stroked twice when the theme asks for it: a wide translucent
    /// glow under a crisp core, which is what makes the trail read as *lit* on a
    /// dark map rather than as a flat polyline.
    ///
    /// An **inferred** leg is stroked once, dashed, thinner and unlit. Kamome
    /// does not know how the traveler got across it — the line is a straight
    /// guess between two photo positions — and the published film is where that
    /// has to be visible, because the film is what gets shared. Giving it the
    /// glowing treatment would be claiming a road we never proved.
    func drawRouteLeg(_ leg: RecapRouteLeg, into surface: RenderSurface) {
        guard leg.coordinates.count >= 2 else { return }
        let context = surface.context
        let path = CGMutablePath()
        path.move(to: surface.cgPoint(lat: leg.coordinates[0].lat, lon: leg.coordinates[0].lon))
        for coordinate in leg.coordinates.dropFirst() {
            path.addLine(to: surface.cgPoint(lat: coordinate.lat, lon: coordinate.lon))
        }
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        defer { context.restoreGState() }

        guard !leg.provenance.isInferred else {
            let scale = surface.scale
            context.setLineDash(
                phase: 0, lengths: [style.routeInferredDashPx * scale, style.routeInferredGapPx * scale]
            )
            context.setStrokeColor(style.routeInferredColor)
            context.setLineWidth(style.routeWidthPx * style.routeInferredWidthMultiple * scale)
            context.addPath(path)
            context.strokePath()
            return
        }

        if (style.routeGlowColor.alpha) > 0.001 {
            context.setStrokeColor(style.routeGlowColor)
            context.setLineWidth(style.routeWidthPx * style.routeGlowWidthMultiple * surface.scale)
            context.addPath(path)
            context.strokePath()
        }
        context.setStrokeColor(style.routeColor)
        context.setLineWidth(style.routeWidthPx * surface.scale)
        context.addPath(path)
        context.strokePath()
    }
}
