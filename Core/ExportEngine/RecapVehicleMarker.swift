import CoreGraphics
import Foundation

/// The moving subject drawn at the vehicle position (§4.5 step 1, prototype
/// §2.3 — "the vehicle is the subject," not a dot on a wide map). A top-down
/// **car** is the default; the seagull (brand mascot), scooter, and bike are
/// swappable through the overlay token on `RecapStyle`, so nothing hardwires
/// the car (Chiu 2026-07-20: seagull is no longer forced as the moving marker).
///
/// Each marker is drawn as pure CoreGraphics vector paths — no image assets —
/// so the whole pipeline stays deterministic for the golden-frame gate. Shapes
/// are authored in a normalized local frame (forward = +y, unit length 1.0,
/// centered on the origin) and scaled to `lengthPx`; the origin is always
/// covered so the marker reads as a solid subject at its center.
public enum VehicleMarker: String, CaseIterable {
    case car
    case seagull
    case scooter
    case bike

    /// The marker's three fills: body, glass/wheels, and contrast edge.
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
    /// its nose pointing `rotationDegrees` clockwise from screen-up. `fill` is
    /// the body, `accent` the glass/wheels, `outline` the contrast edge.
    public func draw(
        in context: CGContext,
        at center: CGPoint,
        lengthPx: CGFloat,
        rotationDegrees: Double,
        colors: Palette
    ) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        // The compositor frame is y-up; a clockwise-from-up screen rotation is a
        // negative math-angle rotation there (see screenRotationDegrees).
        context.rotate(by: -rotationDegrees * .pi / 180)
        context.scaleBy(x: lengthPx, y: lengthPx)
        // Outline scales with the marker but not with the unit path transform.
        let width = 0.045

        switch self {
        case .car:
            drawCar(in: context, colors: colors, outlineWidth: width)
        case .scooter:
            drawScooter(in: context, colors: colors, outlineWidth: width)
        case .bike:
            drawBike(in: context, colors: colors, outlineWidth: width)
        case .seagull:
            drawSeagull(in: context, colors: colors, outlineWidth: width)
        }
        context.restoreGState()
    }

    // MARK: - Silhouettes (unit local frame: forward = +y, length 1.0)

    private func drawCar(in context: CGContext, colors: Palette, outlineWidth: CGFloat) {
        // Body: a rounded rect, nose (+y) slightly narrower than the tail.
        let body = CGPath(
            roundedRect: CGRect(x: -0.24, y: -0.5, width: 0.48, height: 1.0),
            cornerWidth: 0.2, cornerHeight: 0.24, transform: nil
        )
        fillStroke(context, path: body, fill: colors.fill, outline: colors.outline, width: outlineWidth)

        // Windscreen (front) + rear window: tinted glass, kept off dead-center
        // so the origin stays solid body.
        let windshield = CGPath(
            roundedRect: CGRect(x: -0.17, y: 0.12, width: 0.34, height: 0.2),
            cornerWidth: 0.08, cornerHeight: 0.08, transform: nil
        )
        let rearWindow = CGPath(
            roundedRect: CGRect(x: -0.17, y: -0.32, width: 0.34, height: 0.18),
            cornerWidth: 0.08, cornerHeight: 0.08, transform: nil
        )
        context.setFillColor(colors.accent)
        context.addPath(windshield)
        context.addPath(rearWindow)
        context.fillPath()

        // Headlights at the very nose.
        context.setFillColor(colors.accent)
        for side in [-1.0, 1.0] as [CGFloat] {
            context.addPath(CGPath(
                roundedRect: CGRect(x: side * 0.16 - 0.05, y: 0.42, width: 0.1, height: 0.05),
                cornerWidth: 0.025, cornerHeight: 0.025, transform: nil
            ))
        }
        context.fillPath()
    }

    private func drawScooter(in context: CGContext, colors: Palette, outlineWidth: CGFloat) {
        // Narrow deck, distinct from the car's wide body.
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
        context.setFillColor(colors.accent)
        for centerY in [0.34, -0.34] as [CGFloat] {
            context.addEllipse(in: CGRect(x: -0.14, y: centerY - 0.14, width: 0.28, height: 0.28))
        }
        context.fillPath()
        context.setLineWidth(outlineWidth)
        context.setStrokeColor(colors.outline)
        for centerY in [0.34, -0.34] as [CGFloat] {
            context.addEllipse(in: CGRect(x: -0.14, y: centerY - 0.14, width: 0.28, height: 0.28))
        }
        context.strokePath()
    }

    private func drawSeagull(in context: CGContext, colors: Palette, outlineWidth: CGFloat) {
        // Ported from the prototype's GULL (recap_engine.html) — the earlier
        // seagull Chiu preferred: a single flowing double-arc, stroked (not
        // filled), round caps. SVG viewBox spans ±24 / ±16 with wingtips at
        // (±20, 5) and the head dipping up to (0, −2); forward (+y here) is
        // SVG −y, and the span normalizes so the wingspan ≈ 1 unit.
        let unit = 1.0 / 40.0
        func point(_ svgX: Double, _ svgY: Double) -> CGPoint {
            CGPoint(x: svgX * unit, y: -svgY * unit)
        }
        let gull = CGMutablePath()
        gull.move(to: point(-20, 5))
        gull.addCurve(to: point(0, -2), control1: point(-11, -11), control2: point(-5, -11))
        gull.addCurve(to: point(20, 5), control1: point(5, -11), control2: point(11, -11))
        context.setStrokeColor(colors.fill)
        context.setLineWidth(6.5 * unit)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(gull)
        context.strokePath()
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
