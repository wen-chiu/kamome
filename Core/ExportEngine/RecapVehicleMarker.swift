import CoreGraphics
import Foundation

/// The **vector** moving subjects (§4.5 step 1, prototype §2.3 — "the vehicle is
/// the subject," not a dot on a wide map). These are simple enough that
/// code-drawn paths look right: the seagull (brand mascot), a scooter, a bike.
///
/// The **car is not here** — code-drawn cars hit a quality ceiling (Chiu
/// 2026-07-25) and it ships as a raster sprite instead (`RecapCarSprite`,
/// `SubjectVisual.rasterSprite`). The `VehicleSilhouette` protocol that existed
/// to make cars swappable went with it; these markers draw directly, which is
/// all a handful of simple shapes ever needed.
///
/// Shapes are authored in a normalized local frame (forward = +y, unit length
/// 1.0, centered on the origin) and scaled to `lengthPx`; the origin is always
/// covered so the marker reads as a solid subject at its center. Unlike the
/// raster sprite, these *may* be rotated to the travel heading — a stroked
/// vector shape survives rotation where a shaded 3/4 photo-real sprite does not.
public enum VehicleMarker: String, CaseIterable {
    case seagull
    case seagullBadge
    case scooter
    case bike

    /// The marker's three roles — **not every marker uses all three**, and that
    /// is by design rather than by oversight.
    ///
    /// Read generally: `fill` is the body, `accent` is what is drawn *on* the
    /// body, `outline` is the contrast edge. For the line-art markers that is
    /// literally deck/handlebar/edge. The bare `.seagull` is a single stroked
    /// arc and uses **only `fill`**; `.seagullBadge` is a disc with a mark on it
    /// and uses **`fill` and `accent`**, its ring and its gull being one colour.
    ///
    /// Documented here because it was previously stated only in a
    /// `RecapStylePresets` comment, several files away from the type it
    /// describes — which is how `markerColor` came to have no reader at all.
    public struct Palette {
        public let fill: CGColor
        public let accent: CGColor
        public let outline: CGColor

        public init(fill: CGColor, accent: CGColor, outline: CGColor) {
            self.fill = fill
            self.accent = accent
            self.outline = outline
        }
    }

    /// On-screen rotation for the marker: the geographic travel `heading`
    /// minus the map `bearing`. North-up map (bearing 0) → the marker rotates
    /// to point along the route; heading-up map (bearing == heading in the
    /// follow body) → the world rotates and the marker points straight up, the
    /// TravelBoast reading. Degrees clockwise from screen-up, normalized [0,360).
    public static func screenRotationDegrees(heading: Double, bearing: Double) -> Double {
        let raw = (heading - bearing).truncatingRemainder(dividingBy: 360)
        return raw < 0 ? raw + 360 : raw
    }

    /// Draws the marker centered at `center` (in the compositor's y-up frame),
    /// its nose pointing `rotationDegrees` clockwise from screen-up.
    public func draw(
        in context: CGContext,
        at center: CGPoint,
        lengthPx: CGFloat,
        rotationDegrees: Double,
        colors: Palette
    ) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        if rotates {
            // The compositor frame is y-up; a clockwise-from-up screen rotation is a
            // negative math-angle rotation there (see screenRotationDegrees).
            context.rotate(by: -rotationDegrees * .pi / 180)
        }
        context.scaleBy(x: lengthPx, y: lengthPx)
        // Outline scales with the marker but not with the unit path transform.
        let width = 0.045
        switch self {
        case .scooter: drawScooter(in: context, colors: colors, outlineWidth: width)
        case .bike: drawBike(in: context, colors: colors, outlineWidth: width)
        case .seagull: drawSeagull(in: context, colors: colors)
        case .seagullBadge: drawSeagullBadge(in: context, colors: colors)
        }
        context.restoreGState()
    }

    /// Whether the travel heading turns this marker.
    ///
    /// The badge does not. Its disc is rotationally symmetric, so rotating it
    /// only spins the gull inside a circle that never appears to move — and a
    /// badge reads as chrome, which is upright. The meaning agrees with the
    /// geometry: the badge is drawn when Kamome could not work out *what* was
    /// travelling, which is not a claim about which way it was pointed. The
    /// trail still carries the direction.
    var rotates: Bool {
        switch self {
        case .seagull, .scooter, .bike: return true
        case .seagullBadge: return false
        }
    }

    // MARK: - Silhouettes (unit local frame: forward = +y, length 1.0)

    private func drawScooter(in context: CGContext, colors: Palette, outlineWidth: CGFloat) {
        // Narrow deck, distinct from a car's wide body.
        let deck = CGPath(
            roundedRect: CGRect(x: -0.14, y: -0.42, width: 0.28, height: 0.84),
            cornerWidth: 0.13, cornerHeight: 0.16, transform: nil
        )
        fillStroke(context, path: deck, fill: colors.fill, outline: colors.outline, width: outlineWidth)
        // Handlebar across the nose + a seat pad toward the tail.
        context.setFillColor(colors.accent)
        context.addPath(CGPath(
            roundedRect: CGRect(x: -0.26, y: 0.3, width: 0.52, height: 0.08),
            cornerWidth: 0.04, cornerHeight: 0.04, transform: nil
        ))
        context.addPath(CGPath(
            roundedRect: CGRect(x: -0.1, y: -0.28, width: 0.2, height: 0.22),
            cornerWidth: 0.06, cornerHeight: 0.06, transform: nil
        ))
        context.fillPath()
    }

    private func drawBike(in context: CGContext, colors: Palette, outlineWidth: CGFloat) {
        // Thin frame down the center so the origin is covered.
        let frame = CGPath(
            roundedRect: CGRect(x: -0.05, y: -0.34, width: 0.1, height: 0.68),
            cornerWidth: 0.05, cornerHeight: 0.05, transform: nil
        )
        fillStroke(context, path: frame, fill: colors.fill, outline: colors.outline, width: outlineWidth)
        // Handlebar across the nose.
        context.setFillColor(colors.fill)
        context.addPath(CGPath(
            roundedRect: CGRect(x: -0.2, y: 0.24, width: 0.4, height: 0.07),
            cornerWidth: 0.035, cornerHeight: 0.035, transform: nil
        ))
        context.fillPath()
        // Two wheels front and back.
        for centerY in [0.34, -0.34] as [CGFloat] {
            let wheel = CGPath(
                ellipseIn: CGRect(x: -0.14, y: centerY - 0.14, width: 0.28, height: 0.28), transform: nil
            )
            fillStroke(context, path: wheel, fill: colors.accent, outline: colors.outline, width: outlineWidth)
        }
    }

    /// The gull vector itself, shared by the bare marker and the badge so the
    /// bird is drawn from one path. Ported from the prototype's GULL
    /// (recap_engine.html) — the earlier seagull Chiu preferred: a single
    /// flowing double-arc, stroked (not filled), round caps. SVG viewBox spans
    /// ±24 / ±16 with wingtips at (±20, 5) and the head dipping up to (0, −2);
    /// forward (+y here) is SVG −y, and the span normalizes so the wingspan ≈ 1
    /// unit.
    private static let gullUnit = 1.0 / 40.0
    private static let gullStrokeWidth = 6.5 * gullUnit

    private static func gullPath() -> CGPath {
        func point(_ svgX: Double, _ svgY: Double) -> CGPoint {
            CGPoint(x: svgX * gullUnit, y: -svgY * gullUnit)
        }
        let gull = CGMutablePath()
        gull.move(to: point(-20, 5))
        gull.addCurve(to: point(0, -2), control1: point(-11, -11), control2: point(-5, -11))
        gull.addCurve(to: point(20, 5), control1: point(5, -11), control2: point(11, -11))
        return gull
    }

    private static func strokeGull(in context: CGContext, color: CGColor, width: CGFloat) {
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(gullPath())
        context.strokePath()
    }

    private func drawSeagull(in context: CGContext, colors: Palette) {
        Self.strokeGull(in: context, color: colors.fill, width: Self.gullStrokeWidth)
    }

    /// **The badge** (Chiu 2026-08-29): a disc, a ring around it, and the gull in
    /// the middle — ring and gull sharing one colour against the disc.
    ///
    /// Why this shape rather than a better colour. A bare gull is only as visible
    /// as the difference between its ink and whatever it is flying over, and that
    /// difference moves: measured on one Iceland frame, the same gull sat against
    /// 190.9 luminance where it crossed the trail and the sea, and roughly 236
    /// over clean land. Every colour dark enough to clear the contrast bar on a
    /// pale map is also too dark for its hue to register — which is why the navy
    /// sweep did not read as blue. **A badge carries its own contrast**: the ring
    /// reads against the disc and the gull reads against the disc, whatever is
    /// underneath. Terrain stops being a variable.
    ///
    /// It also separates two jobs that were competing for one drawing. A badge
    /// reads as a marker; a bare bird reads as a bird. `.seagull` stays exactly
    /// as it was for the end-card brand mark, and stays free for the
    /// cross-region narrator `Docs/cross-region-journeys.md` requirement 4 wants.
    private func drawSeagullBadge(in context: CGContext, colors: Palette) {
        // The unit length is the badge's diameter, so `lengthPx` still means "how
        // much room the subject takes", the same as every other marker.
        let radius = 0.5
        // Thick enough to survive the 1080-wide reference at the sizes this
        // subject is drawn at; thin enough not to crowd the bird.
        let ringWidth = 0.085
        context.setFillColor(colors.fill)
        context.fillEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
        let ringRadius = radius - ringWidth / 2
        context.setStrokeColor(colors.accent)
        context.setLineWidth(ringWidth)
        context.strokeEllipse(in: CGRect(
            x: -ringRadius, y: -ringRadius, width: ringRadius * 2, height: ringRadius * 2
        ))
        // The gull spans ~1.16 units including its own stroke, so it is scaled to
        // sit inside the ring with air around the wingtips, and nudged up by its
        // own vertical centre — the path is authored around the wing line, not
        // around the shape's middle.
        context.saveGState()
        context.scaleBy(x: 0.52, y: 0.52)
        context.translateBy(x: 0, y: 0.037)
        Self.strokeGull(in: context, color: colors.accent, width: Self.gullStrokeWidth)
        context.restoreGState()
    }

    private func fillStroke(
        _ context: CGContext, path: CGPath, fill: CGColor, outline: CGColor, width: CGFloat
    ) {
        context.setFillColor(fill)
        context.addPath(path)
        context.fillPath()
        context.setStrokeColor(outline)
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.addPath(path)
        context.strokePath()
    }
}
