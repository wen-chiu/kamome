import CoreGraphics
import Foundation

/// **The marks the boarding pass is made of** — split out of
/// `RecapOverlayJourneyCardDrawing` on 2026-09-04, when laying the card out to
/// Chiu's mockup took that file past its 400-line budget.
///
/// The split is layout versus ornament: the other file decides where the stub,
/// the two ends and the bottom row sit, and this one draws the things that fill
/// them — the dashed arc with its two endpoints, the aircraft riding it, the dot
/// field behind it, and the row's two icons. Nothing here knows what a crossing
/// is; it takes points and rectangles.
extension RecapOverlayRenderer {
    // MARK: - The arc

    /// The dotted great-circle nod, its two endpoints, and the aircraft on it,
    /// over a plain dot field.
    ///
    /// A quadratic bow rather than a straight line: it is the one shape that says
    /// *flight* on a ticket, and it costs nothing to draw.
    func drawArc(progress: CGFloat, from: CGPoint, to: CGPoint, in surface: RenderSurface) {
        let tokens = style.journeyCard
        let context = surface.context
        let scale = surface.scale
        let rise = (to.x - from.x) * tokens.arcRiseFraction
        let control = CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + rise)

        context.saveGState()
        context.clip(to: CGRect(
            x: from.x, y: from.y - rise * 0.2, width: to.x - from.x, height: rise * 1.4
        ))
        drawGroundDots(in: CGRect(
            x: from.x, y: from.y - rise * 0.2, width: to.x - from.x, height: rise * 1.4
        ), in: surface)
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(tokens.ruleColor)
        context.setLineWidth(tokens.arcWidthPx * scale)
        context.setLineCap(.round)
        context.setLineDash(phase: 0, lengths: [tokens.arcDashPx * scale, tokens.arcGapPx * scale])
        context.move(to: from)
        context.addQuadCurve(to: to, control: control)
        context.strokePath()
        context.restoreGState()

        // The origin is filled and the destination is an open ring — the mockup's
        // way of saying which end you have already left.
        let dot = tokens.endpointRadiusPx * scale
        context.setFillColor(tokens.accentColor)
        context.fillEllipse(in: CGRect(x: from.x - dot, y: from.y - dot, width: dot * 2, height: dot * 2))
        context.setStrokeColor(tokens.inkColor)
        context.setLineWidth(scale * 1.5)
        context.strokeEllipse(in: CGRect(x: to.x - dot, y: to.y - dot, width: dot * 2, height: dot * 2))

        // Position and heading from the same quadratic, so the glyph rides the
        // line rather than sitting near it.
        let clamped = min(max(progress, 0), 1)
        let point = Self.quadratic(from: from, control: control, to: to, at: clamped)
        let ahead = Self.quadratic(from: from, control: control, to: to, at: min(clamped + 0.02, 1))
        drawPlane(
            at: point, headingRadians: atan2(ahead.y - point.y, ahead.x - point.x),
            lengthPx: tokens.planeLengthPx * scale, in: surface
        )
    }

    static func quadratic(
        from: CGPoint, control: CGPoint, to: CGPoint, at fraction: CGFloat
    ) -> CGPoint {
        let inverse = 1 - fraction
        return CGPoint(
            x: inverse * inverse * from.x + 2 * inverse * fraction * control.x + fraction * fraction * to.x,
            y: inverse * inverse * from.y + 2 * inverse * fraction * control.y + fraction * fraction * to.y
        )
    }

    /// The faint regular dot field the arc sits on. **Not a world map**: a drawn
    /// coastline would be a second claim about where places are, and this card's
    /// job is to name two of them, not to draw the planet.
    func drawGroundDots(in rect: CGRect, in surface: RenderSurface) {
        let tokens = style.journeyCard
        let context = surface.context
        guard let colour = tokens.ruleColor.copy(alpha: tokens.groundDotAlpha) else { return }
        let pitch = tokens.groundDotPitchPx * surface.scale
        let radius = tokens.groundDotRadiusPx * surface.scale
        guard pitch > 0 else { return }
        context.saveGState()
        context.setFillColor(colour)
        var dotY = rect.minY
        while dotY <= rect.maxY {
            var dotX = rect.minX
            while dotX <= rect.maxX {
                context.fillEllipse(in: CGRect(
                    x: dotX - radius, y: dotY - radius, width: radius * 2, height: radius * 2
                ))
                dotX += pitch
            }
            dotY += pitch
        }
        context.restoreGState()
    }

    /// A printed aircraft glyph — a swept dart, drawn nose-first along +x.
    ///
    /// ⚠️ **Not the map's crossing subject**, which is the `plane` sprite set
    /// since ADR 2026-09-04. This is ticket furniture on a fixed-size card: it
    /// does not scale with the frame and it is not what flies across the map.
    func drawPlane(
        at center: CGPoint, headingRadians: CGFloat, lengthPx: CGFloat,
        color: CGColor? = nil, in surface: RenderSurface
    ) {
        let context = surface.context
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: headingRadians)
        let half = lengthPx / 2
        let wing = lengthPx * 0.46
        context.beginPath()
        context.move(to: CGPoint(x: half, y: 0))                       // nose
        context.addLine(to: CGPoint(x: -half * 0.15, y: wing / 2))     // port wing
        context.addLine(to: CGPoint(x: -half * 0.42, y: wing / 2))
        context.addLine(to: CGPoint(x: -half * 0.2, y: 0))
        context.addLine(to: CGPoint(x: -half * 0.42, y: -wing / 2))    // starboard wing
        context.addLine(to: CGPoint(x: -half * 0.15, y: -wing / 2))
        context.closePath()
        context.setFillColor(color ?? style.journeyCard.accentColor)
        context.fillPath()
    }

    /// The bottom row's two marks. Internal, not private: the row is laid out in
    /// `RecapOverlayJourneyCardDrawing` and drawn here, and Swift scopes
    /// `private` to the file.
    enum CardIcon { case plane, calendar }

    /// The row's two marks, drawn rather than bundled: two outlines at this size
    /// are a few paths each, and an asset would be two more files to keep in step
    /// with the palette.
    func drawIcon(_ icon: CardIcon, in rect: CGRect, in surface: RenderSurface) {
        let context = surface.context
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(style.journeyCard.mutedColor)
        context.setFillColor(style.journeyCard.mutedColor)
        context.setLineWidth(surface.scale * 1.6)
        switch icon {
        case .plane:
            // Muted, like the calendar beside it: the row's marks label the
            // fields, they do not repeat the accent the arc's aircraft carries.
            drawPlane(
                at: CGPoint(x: rect.midX, y: rect.midY), headingRadians: .pi / 2,
                lengthPx: rect.width, color: style.journeyCard.mutedColor, in: surface
            )
        case .calendar:
            let body = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.14)
            context.stroke(body)
            context.move(to: CGPoint(x: body.minX, y: body.maxY - body.height * 0.28))
            context.addLine(to: CGPoint(x: body.maxX, y: body.maxY - body.height * 0.28))
            context.strokePath()
            for column in 0..<3 {
                let dot = body.width * 0.11
                context.fillEllipse(in: CGRect(
                    x: body.minX + body.width * (0.22 + 0.28 * CGFloat(column)),
                    y: body.minY + body.height * 0.24, width: dot, height: dot
                ))
            }
        }
    }
}

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
    /// ⚠️ **`VehicleMarker.seagull`, sized and coloured here and never reshaped.**
    /// It is the same bird as the end card's wordmark, and restyling it in place
    /// would silently change the brand mark on every film (`HANDOFF.md`
    /// 2026-08-29 finding 5b). The three other gull objects are all wrong for
    /// this: `seagull/logo.png` must not reach the renderer, `omni.png` is the
    /// *subject* sprite and would say "a seagull flies this leg" now that a plane
    /// does, and `.seagullBadge` means "the artwork failed to load".
    func drawFlightEnds(
        origin: RecapCoordinate?, destination: RecapCoordinate, opacity: Double,
        into surface: RenderSurface
    ) {
        guard opacity > 0.001 else { return }
        let context = surface.context
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(CGFloat(opacity))
        for end in [origin, destination].compactMap({ $0 }) {
            VehicleMarker.seagull.draw(
                in: context,
                at: surface.cgPoint(lat: end.lat, lon: end.lon),
                lengthPx: style.flightEndMarkLengthPx * surface.scale,
                rotationDegrees: 0,
                colors: VehicleMarker.Palette(
                    fill: style.labelTextColor,
                    accent: style.labelTextColor,
                    outline: style.labelShadowColor
                )
            )
        }
    }
}
