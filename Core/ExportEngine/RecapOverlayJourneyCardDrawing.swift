import CoreGraphics
import Foundation

/// **The boarding pass**, drawn for the crossing beat and nothing else (Chiu
/// 2026-09-02). Its own file, like the route, deck, HUD and chrome drawings
/// before it — `RecapOverlayRenderer.swift` sits at 318 lines against a 400-line
/// budget, and this is a self-contained drawing rather than a slice of one.
///
/// ## What is on it, and the one thing that is not
///
/// `FROM` / `TO` with each region named in English over the viewer's own
/// language, a dotted arc with the aircraft travelling it, the flight's distance
/// **labelled as the flight**, the two dates, and the constant flight number on a
/// perforated stub.
///
/// 🔴 **No `FLIGHT TIME`.** Kamome does not know when the aircraft left or landed,
/// so it cannot compute one, and a number it does not have printed on something
/// shaped like a document is a fabricated record (`CLAUDE.md` rule 5).
///
/// 🔴 **The field labels are English literals, and that is deliberate, not an
/// i18n oversight.** A boarding pass is an English artefact — `FROM`, `TO`,
/// `DISTANCE`, `FLIGHT` read as ticket furniture in every market, and localising
/// them would make the object stop being the thing it is imitating. The *place
/// names* are localized, which is where the viewer's language belongs.
extension RecapOverlayRenderer {
    func drawJourneyCard(_ card: RecapJourneyCard, into surface: RenderSurface) {
        guard card.opacity > 0.001 else { return }
        let tokens = style.journeyCard
        let scale = surface.scale
        let width = CGFloat(surface.widthPx) * tokens.widthFraction
        let rect = CGRect(
            x: (CGFloat(surface.widthPx) - width) / 2,
            y: CGFloat(surface.heightPx) * tokens.centerFraction - width * tokens.aspect / 2,
            width: width, height: width * tokens.aspect
        )

        surface.context.saveGState()
        defer { surface.context.restoreGState() }
        surface.context.setAlpha(CGFloat(card.opacity))

        drawStock(rect, in: surface)
        let stubX = rect.minX + rect.width * tokens.stubFraction
        drawPerforation(atX: stubX, in: rect, surface: surface)
        drawStub(card, in: CGRect(
            x: stubX, y: rect.minY, width: rect.maxX - stubX, height: rect.height
        ), surface: surface)

        let body = CGRect(
            x: rect.minX + tokens.paddingPx * scale, y: rect.minY + tokens.paddingPx * scale,
            width: stubX - rect.minX - tokens.paddingPx * 2 * scale,
            height: rect.height - tokens.paddingPx * 2 * scale
        )
        drawEnds(card, in: body, surface: surface)
        drawBottomRow(card, in: body, surface: surface)
    }

    /// The card stock: rounded, shadowed, opaque enough to be a printed object
    /// rather than a translucent panel.
    private func drawStock(_ rect: CGRect, in surface: RenderSurface) {
        let tokens = style.journeyCard
        let context = surface.context
        let corner = tokens.cornerPx * surface.scale
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -tokens.shadowOffsetPx * surface.scale),
            blur: tokens.shadowBlurPx * surface.scale, color: tokens.shadowColor
        )
        context.setFillColor(tokens.stockColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.fillPath()
        context.restoreGState()
    }

    /// The tear line, and the two notches that make a rectangle read as a ticket.
    /// The notches are punched in the frame's own background rather than in the
    /// stock, because CoreGraphics has no subtract-path and the map behind is not
    /// a colour this drawing knows.
    private func drawPerforation(atX tearX: CGFloat, in rect: CGRect, surface: RenderSurface) {
        let tokens = style.journeyCard
        let context = surface.context
        let scale = surface.scale
        let radius = tokens.notchRadiusPx * scale

        context.saveGState()
        context.setBlendMode(.destinationOut)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for centerY in [rect.minY, rect.maxY] {
            context.fillEllipse(in: CGRect(
                x: tearX - radius, y: centerY - radius, width: radius * 2, height: radius * 2
            ))
        }
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(tokens.mutedColor)
        context.setLineWidth(tokens.arcWidthPx * scale * 0.6)
        context.setLineDash(phase: 0, lengths: [
            tokens.perforationDashPx * scale, tokens.perforationGapPx * scale
        ])
        context.move(to: CGPoint(x: tearX, y: rect.minY + radius))
        context.addLine(to: CGPoint(x: tearX, y: rect.maxY - radius))
        context.strokePath()
        context.restoreGState()
    }

    /// The stub: the brand mark and the flight number, rotated to read up the
    /// card the way a real tear-off does.
    private func drawStub(_ card: RecapJourneyCard, in rect: CGRect, surface: RenderSurface) {
        let tokens = style.journeyCard
        let context = surface.context
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: -.pi / 2)
        drawCardText(
            RecapJourneyCard.flightNumber, centeredAt: CGPoint(x: 0, y: 0),
            fontPx: tokens.flightFontPx, color: tokens.accentColor,
            tracking: tokens.flightFontPx * tokens.labelTrackingEm * surface.scale, in: surface
        )
        drawCardText(
            "BOARDING PASS", centeredAt: CGPoint(x: 0, y: -tokens.flightFontPx * surface.scale * 1.15),
            fontPx: tokens.labelFontPx, color: tokens.mutedColor,
            tracking: tokens.labelFontPx * tokens.labelTrackingEm * surface.scale, in: surface
        )
    }

    /// `FROM` and `TO`, each named twice, with the dotted arc between them.
    private func drawEnds(_ card: RecapJourneyCard, in body: CGRect, surface: RenderSurface) {
        let tokens = style.journeyCard
        let scale = surface.scale
        let columnW = body.width * 0.34
        let top = body.maxY
        /// One printed end of the flight: which column it sits in and what the
        /// field above it says. A named shape rather than a 3-tuple — the lint
        /// bar is two members, and "region/label/x" is exactly the kind of triple
        /// that reads fine here and badly at the call site.
        struct End {
            let region: RecapJourneyCard.Region
            let label: String
            let centerX: CGFloat
        }
        for end in [
            End(region: card.from, label: "FROM", centerX: body.minX + columnW / 2),
            End(region: card.to, label: "TO", centerX: body.maxX - columnW / 2)
        ] {
            let (region, label, centerX) = (end.region, end.label, end.centerX)
            drawCardText(
                label, centeredAt: CGPoint(x: centerX, y: top - tokens.labelFontPx * scale),
                fontPx: tokens.labelFontPx, color: tokens.mutedColor,
                tracking: tokens.labelFontPx * tokens.labelTrackingEm * scale, in: surface
            )
            // The place name is user-facing data of any length, so it shrinks to
            // its column rather than running into the arc — the same rule the stop
            // label and the title follow.
            let fitted = fittedFontPx(
                region.english, preferred: tokens.regionFontPx, maxWidth: columnW, in: surface
            )
            drawCardText(
                region.english,
                centeredAt: CGPoint(x: centerX, y: top - tokens.labelFontPx * scale * 2.6),
                fontPx: fitted, color: tokens.inkColor, tracking: 0, in: surface
            )
            guard let local = region.local else { continue }
            drawCardText(
                local,
                centeredAt: CGPoint(x: centerX, y: top - tokens.labelFontPx * scale * 2.6 - fitted * scale),
                fontPx: fittedFontPx(local, preferred: tokens.localFontPx, maxWidth: columnW, in: surface),
                color: tokens.mutedColor, tracking: 0, in: surface
            )
        }
        drawArc(
            progress: CGFloat(card.progress),
            from: CGPoint(x: body.minX + columnW, y: top - tokens.labelFontPx * scale * 2.0),
            to: CGPoint(x: body.maxX - columnW, y: top - tokens.labelFontPx * scale * 2.0),
            in: surface
        )
    }

    /// The dotted great-circle nod, and the aircraft on it.
    ///
    /// A quadratic bow rather than a straight line: it is the one shape that says
    /// *flight* on a ticket, and it costs nothing to draw.
    private func drawArc(progress: CGFloat, from: CGPoint, to: CGPoint, in surface: RenderSurface) {
        let tokens = style.journeyCard
        let context = surface.context
        let scale = surface.scale
        let rise = (to.x - from.x) * tokens.arcRiseFraction
        let control = CGPoint(x: (from.x + to.x) / 2, y: max(from.y, to.y) + rise)

        context.saveGState()
        context.setStrokeColor(tokens.mutedColor)
        context.setLineWidth(tokens.arcWidthPx * scale)
        context.setLineCap(.round)
        context.setLineDash(phase: 0, lengths: [tokens.arcDashPx * scale, tokens.arcGapPx * scale])
        context.move(to: from)
        context.addQuadCurve(to: to, control: control)
        context.strokePath()
        context.restoreGState()

        // Position and heading from the same quadratic, so the glyph is on the
        // line it is riding rather than near it.
        let clamped = min(max(progress, 0), 1)
        let point = Self.quadratic(from: from, control: control, to: to, at: clamped)
        let ahead = Self.quadratic(
            from: from, control: control, to: to, at: min(clamped + 0.02, 1)
        )
        drawPlane(
            at: point, headingRadians: atan2(ahead.y - point.y, ahead.x - point.x),
            lengthPx: tokens.planeLengthPx * scale, in: surface
        )
    }

    private static func quadratic(
        from: CGPoint, control: CGPoint, to: CGPoint, at fraction: CGFloat
    ) -> CGPoint {
        let inverse = 1 - fraction
        return CGPoint(
            x: inverse * inverse * from.x + 2 * inverse * fraction * control.x + fraction * fraction * to.x,
            y: inverse * inverse * from.y + 2 * inverse * fraction * control.y + fraction * fraction * to.y
        )
    }

    /// A printed aircraft glyph — a swept dart, drawn nose-first along +x.
    ///
    /// ⚠️ **Not the map's crossing subject.** That is still the car sprite and is
    /// the mode classifier's to fix (crossing session 2). This is ticket
    /// furniture on a fixed-size card, and giving it a plane here makes no claim
    /// about what flies across the map.
    private func drawPlane(
        at center: CGPoint, headingRadians: CGFloat, lengthPx: CGFloat, in surface: RenderSurface
    ) {
        let context = surface.context
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: headingRadians)
        let half = lengthPx / 2
        let wing = lengthPx * 0.42
        context.beginPath()
        context.move(to: CGPoint(x: half, y: 0))                       // nose
        context.addLine(to: CGPoint(x: -half * 0.15, y: wing / 2))     // port wing
        context.addLine(to: CGPoint(x: -half * 0.42, y: wing / 2))
        context.addLine(to: CGPoint(x: -half * 0.2, y: 0))
        context.addLine(to: CGPoint(x: -half * 0.42, y: -wing / 2))    // starboard wing
        context.addLine(to: CGPoint(x: -half * 0.15, y: -wing / 2))
        context.closePath()
        context.setFillColor(style.journeyCard.accentColor)
        context.fillPath()
    }

    /// `DISTANCE` and the dates — the pass's bottom row.
    ///
    /// 🔴 **This is the only flown figure in the film, and it says so.** Every
    /// other kilometre a viewer reads — the HUD odometer, the title card's
    /// subtitle, the end card's stats — is the local journey (Chiu 2026-09-02).
    /// The label is what stops the two being read as the same quantity.
    private func drawBottomRow(_ card: RecapJourneyCard, in body: CGRect, surface: RenderSurface) {
        let tokens = style.journeyCard
        let scale = surface.scale
        let labelY = body.minY + tokens.valueFontPx * scale * 1.5
        let valueY = body.minY
        let distance = Self.distance(travelledM: card.distanceM)
            .map { "\($0.value) \($0.unit)" } ?? "—"

        drawCardField(
            label: "FLIGHT DISTANCE", value: distance,
            centerX: body.minX + body.width * 0.2, labelY: labelY, valueY: valueY, in: surface
        )
        // No dates is a real state, not a hole to fill: a trip whose photographs
        // carry no `taken_at` has none, and the pass prints what it knows.
        guard let dates = card.dates else { return }
        drawCardField(
            label: "DEPARTED", value: dates.departure,
            centerX: body.minX + body.width * 0.55, labelY: labelY, valueY: valueY, in: surface
        )
        drawCardField(
            label: "ARRIVED", value: dates.arrival,
            centerX: body.minX + body.width * 0.88, labelY: labelY, valueY: valueY, in: surface
        )
    }

    private func drawCardField(
        label: String, value: String, centerX: CGFloat,
        labelY: CGFloat, valueY: CGFloat, in surface: RenderSurface
    ) {
        let tokens = style.journeyCard
        let scale = surface.scale
        drawCardText(
            label, centeredAt: CGPoint(x: centerX, y: labelY), fontPx: tokens.labelFontPx,
            color: tokens.mutedColor, tracking: tokens.labelFontPx * tokens.labelTrackingEm * scale,
            in: surface
        )
        drawCardText(
            value, centeredAt: CGPoint(x: centerX, y: valueY), fontPx: tokens.valueFontPx,
            color: tokens.inkColor, tracking: 0, in: surface
        )
    }

    /// Centred type with no shadow under it — the pass is opaque stock, so the
    /// legibility trick the unplated map labels need would only make the ink look
    /// smudged.
    private func drawCardText(
        _ text: String, centeredAt anchor: CGPoint, fontPx: CGFloat,
        color: CGColor, tracking: CGFloat, in surface: RenderSurface
    ) {
        drawCenteredText(
            text, centerX: anchor.x, baselineY: anchor.y, fontPx: fontPx,
            color: color, tracking: tracking, in: surface
        )
    }
}
