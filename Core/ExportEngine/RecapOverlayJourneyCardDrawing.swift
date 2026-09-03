import CoreGraphics
import Foundation

/// **The boarding pass**, drawn for the crossing beat and nothing else (Chiu
/// 2026-09-02). Its own file, like the route, deck, HUD and chrome drawings
/// before it — `RecapOverlayRenderer.swift` is at 320 lines against a 400-line
/// budget, and this is a self-contained drawing rather than a slice of one.
///
/// **Laid out from Chiu's own mockup** (登機證樣式（完整）), which arrived after
/// the first pass: stub on the left, a wide ticket, the two ends named large with
/// the local name beneath, a dashed arc bowing between them with the aircraft
/// riding it, a hairline, and a labelled bottom row. What the mockup does *not*
/// settle is in `RecapJourneyCardStyle` — read its two ⚠️ before changing a
/// number here.
///
/// ## What is on it, and the one thing that is not
///
/// 🔴 **No `FLIGHT TIME`, and the mockup shows one.** Kamome does not know when
/// the aircraft left or landed, so it cannot compute one, and a number it does
/// not have printed on something shaped like a document is a fabricated record
/// (`CLAUDE.md` rule 5). The field was removed by decision on 2026-09-02; the
/// picture predates that. Do not restore it from the picture.
///
/// 🔴 **The field labels are English literals, and that is deliberate, not an
/// i18n oversight.** A boarding pass is an English artefact — `FROM`, `TO`,
/// `FLIGHT`, `DISTANCE`, `DATE` read as ticket furniture in every market, and
/// localising them would make the object stop being the thing it imitates. The
/// *place names* are localized, which is where the viewer's language belongs.
extension RecapOverlayRenderer {
    func drawJourneyCard(_ card: RecapJourneyCard, into surface: RenderSurface) {
        guard card.opacity > 0.001 else { return }
        let tokens = style.journeyCard
        let width = CGFloat(surface.widthPx) * tokens.widthFraction
        let rect = CGRect(
            x: (CGFloat(surface.widthPx) - width) / 2,
            y: CGFloat(surface.heightPx) * tokens.centerFraction - width * tokens.aspect / 2,
            width: width, height: width * tokens.aspect
        )

        surface.context.saveGState()
        defer { surface.context.restoreGState() }
        surface.context.setAlpha(CGFloat(card.opacity))

        let tearX = rect.minX + rect.width * tokens.stubFraction
        drawStock(rect, tearX: tearX, in: surface)
        drawStub(card, in: CGRect(
            x: rect.minX, y: rect.minY, width: tearX - rect.minX, height: rect.height
        ), surface: surface)
        drawPerforation(atX: tearX, in: rect, surface: surface)
        drawPanel(card, in: CGRect(
            x: tearX, y: rect.minY, width: rect.maxX - tearX, height: rect.height
        ), surface: surface)
    }

    /// The card stock: rounded, shadowed, opaque enough to be a printed object
    /// rather than a translucent panel, with the two tear notches **punched out
    /// of it**.
    ///
    /// 🔴 The notches are holes in a single even-odd path, not a second pass with
    /// `.destinationOut`. That was the first attempt and it rendered as two black
    /// discs: `destinationOut` erases whatever is already in the context, and by
    /// this point that is the map — so it cut through the frame rather than
    /// through the ticket. One compound path can only remove the stock, which is
    /// the whole of what a notch is.
    private func drawStock(_ rect: CGRect, tearX: CGFloat, in surface: RenderSurface) {
        let tokens = style.journeyCard
        let context = surface.context
        let corner = tokens.cornerPx * surface.scale
        let radius = tokens.notchRadiusPx * surface.scale

        let stock = CGMutablePath()
        stock.addRoundedRect(in: rect, cornerWidth: corner, cornerHeight: corner)
        for centerY in [rect.minY, rect.maxY] {
            stock.addEllipse(in: CGRect(
                x: tearX - radius, y: centerY - radius, width: radius * 2, height: radius * 2
            ))
        }

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -tokens.shadowOffsetPx * surface.scale),
            blur: tokens.shadowBlurPx * surface.scale, color: tokens.shadowColor
        )
        context.setFillColor(tokens.stockColor)
        context.addPath(stock)
        context.fillPath(using: .evenOdd)
        context.restoreGState()
    }

    /// The tear line between the notches `drawStock` has already punched.
    private func drawPerforation(atX tearX: CGFloat, in rect: CGRect, surface: RenderSurface) {
        let tokens = style.journeyCard
        let context = surface.context
        let scale = surface.scale
        let radius = tokens.notchRadiusPx * scale

        context.saveGState()
        context.setStrokeColor(tokens.ruleColor)
        context.setLineWidth(tokens.arcWidthPx * scale * 0.8)
        context.setLineDash(phase: 0, lengths: [
            tokens.perforationDashPx * scale, tokens.perforationGapPx * scale
        ])
        context.move(to: CGPoint(x: tearX, y: rect.minY + radius))
        context.addLine(to: CGPoint(x: tearX, y: rect.maxY - radius))
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - The stub

    /// Left of the tear: the gull, the flight number under its rule, and the
    /// dates — the three things a torn-off half still has to carry.
    private func drawStub(_ card: RecapJourneyCard, in rect: CGRect, surface: RenderSurface) {
        let tokens = style.journeyCard
        let scale = surface.scale
        let left = rect.minX + tokens.paddingPx * scale
        let top = rect.maxY

        // The gull is the wordmark's bird, sized and coloured here and never
        // reshaped (`HANDOFF.md` 2026-08-29 finding 5b).
        let mark = tokens.stubMarkLengthPx * scale
        VehicleMarker.seagull.draw(
            in: surface.context,
            at: CGPoint(x: left + mark * 0.4, y: top - tokens.paddingPx * scale - mark / 2),
            lengthPx: mark, rotationDegrees: 0,
            colors: VehicleMarker.Palette(
                fill: tokens.mutedColor, accent: tokens.mutedColor, outline: tokens.mutedColor
            )
        )

        var cursorY = top - rect.height * 0.30
        drawStubField(label: "FLIGHT", value: RecapJourneyCard.flightNumber,
                      left: left, labelY: cursorY, in: surface)

        cursorY -= rect.height * 0.16
        surface.context.saveGState()
        surface.context.setStrokeColor(tokens.accentColor)
        surface.context.setLineWidth(tokens.arcWidthPx * scale)
        surface.context.move(to: CGPoint(x: left, y: cursorY))
        surface.context.addLine(to: CGPoint(x: left + tokens.stubRuleWidthPx * scale, y: cursorY))
        surface.context.strokePath()
        surface.context.restoreGState()

        cursorY -= rect.height * 0.14
        drawStubField(label: "DATE", value: Self.dateRange(card.dates) ?? "—",
                      left: left, labelY: cursorY, in: surface)

        drawWatermark(
            at: CGPoint(x: left + tokens.stubWatermarkRadiusPx * scale,
                        y: rect.minY + tokens.paddingPx * scale + tokens.stubWatermarkRadiusPx * scale),
            in: surface
        )
    }

    /// A left-aligned label over its value — the stub's one repeated shape.
    private func drawStubField(
        label: String, value: String, left: CGFloat, labelY: CGFloat, in surface: RenderSurface
    ) {
        let tokens = style.journeyCard
        let scale = surface.scale
        drawText(
            label, at: CGPoint(x: left, y: labelY), fontPx: tokens.labelFontPx,
            color: tokens.mutedColor, tracking: tokens.labelFontPx * tokens.labelTrackingEm * scale,
            in: surface
        )
        drawText(
            value, at: CGPoint(x: left, y: labelY - tokens.valueFontPx * scale * 1.15),
            fontPx: tokens.valueFontPx, color: tokens.inkColor, in: surface
        )
    }

    /// The dotted disc at the foot of the stub. Ticket furniture, drawn from the
    /// same dot field as the ground behind the arc so the card has one texture.
    private func drawWatermark(at center: CGPoint, in surface: RenderSurface) {
        let tokens = style.journeyCard
        let context = surface.context
        let radius = tokens.stubWatermarkRadiusPx * surface.scale
        context.saveGState()
        context.addEllipse(in: CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
        ))
        context.clip()
        drawGroundDots(in: CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
        ), in: surface)
        context.restoreGState()
    }

    // MARK: - The panel

    /// Right of the tear: the two ends, the arc between them, and the bottom row.
    private func drawPanel(_ card: RecapJourneyCard, in rect: CGRect, surface: RenderSurface) {
        let tokens = style.journeyCard
        let scale = surface.scale
        let body = rect.insetBy(dx: tokens.paddingPx * scale, dy: tokens.paddingPx * scale)
        let ruleY = rect.minY + rect.height * 0.29

        drawEnds(card, in: body, arcBaseY: rect.minY + rect.height * 0.52, surface: surface)

        surface.context.saveGState()
        surface.context.setStrokeColor(tokens.ruleColor)
        surface.context.setLineWidth(scale)
        surface.context.move(to: CGPoint(x: body.minX, y: ruleY))
        surface.context.addLine(to: CGPoint(x: body.maxX, y: ruleY))
        surface.context.strokePath()
        surface.context.restoreGState()

        drawBottomRow(card, in: CGRect(
            x: body.minX, y: body.minY, width: body.width, height: ruleY - body.minY
        ), surface: surface)
    }

    /// `FROM` and `TO`, each named twice, with the dotted arc between them.
    private func drawEnds(
        _ card: RecapJourneyCard, in body: CGRect, arcBaseY: CGFloat, surface: RenderSurface
    ) {
        let tokens = style.journeyCard
        let scale = surface.scale
        let columnW = body.width * 0.36
        let top = body.maxY

        /// One printed end of the flight: which column it sits in, what the field
        /// above it says, and which way its type is aligned. A named shape rather
        /// than a tuple — the lint bar is two members, and this is three facts.
        struct End {
            let region: RecapJourneyCard.Region
            let label: String
            let edgeX: CGFloat
            let alignRight: Bool
        }
        for end in [
            End(region: card.from, label: "FROM", edgeX: body.minX, alignRight: false),
            End(region: card.to, label: "TO", edgeX: body.maxX, alignRight: true)
        ] {
            drawAligned(
                CardType(
                    text: end.label, fontPx: tokens.labelFontPx, color: tokens.accentColor,
                    tracking: tokens.labelFontPx * tokens.labelTrackingEm * scale
                ),
                edgeX: end.edgeX, alignRight: end.alignRight,
                baselineY: top - tokens.labelFontPx * scale, in: surface
            )
            // A place name is user data of any length, so it shrinks to its
            // column rather than running into the arc — the rule the stop label
            // and the title already follow.
            let fitted = fittedFontPx(
                end.region.english, preferred: tokens.regionFontPx, maxWidth: columnW, in: surface
            )
            let nameY = top - tokens.labelFontPx * scale - fitted * scale * 1.25
            drawAligned(
                CardType(text: end.region.english, fontPx: fitted, color: tokens.inkColor),
                edgeX: end.edgeX, alignRight: end.alignRight, baselineY: nameY, in: surface
            )
            guard let local = end.region.local else { continue }
            drawAligned(
                CardType(
                    text: local,
                    fontPx: fittedFontPx(local, preferred: tokens.localFontPx, maxWidth: columnW, in: surface),
                    color: tokens.mutedColor
                ),
                edgeX: end.edgeX, alignRight: end.alignRight,
                baselineY: nameY - tokens.localFontPx * scale * 1.5, in: surface
            )
        }
        drawArc(
            progress: CGFloat(card.progress),
            from: CGPoint(x: body.minX + columnW * 0.92, y: arcBaseY),
            to: CGPoint(x: body.maxX - columnW * 0.92, y: arcBaseY + scale * 6),
            in: surface
        )
    }

    /// One run of type on the card: what it says, how it is set, and which panel
    /// edge it hangs off.
    struct CardType {
        let text: String
        let fontPx: CGFloat
        let color: CGColor
        var tracking: CGFloat = 0
    }

    /// Left- or right-aligned type, so `FROM` hangs off one edge of the panel and
    /// `TO` off the other exactly as the mockup sets them.
    private func drawAligned(
        _ type: CardType, edgeX: CGFloat, alignRight: Bool, baselineY: CGFloat, in surface: RenderSurface
    ) {
        let width = textWidth(type.text, fontPx: type.fontPx, tracking: type.tracking, in: surface)
        drawText(
            type.text, at: CGPoint(x: alignRight ? edgeX - width : edgeX, y: baselineY),
            fontPx: type.fontPx, color: type.color, tracking: type.tracking, in: surface
        )
    }

    // MARK: - The bottom row

    /// `DISTANCE` and `DATE`, each an icon beside a label over its value.
    ///
    /// 🔴 **The distance is the only flown figure in the film, and it says so.**
    /// Every other kilometre a viewer reads — the HUD odometer, the title card's
    /// subtitle, the end card's stats — is the local journey (Chiu 2026-09-02).
    /// The label is what stops the two being read as the same quantity.
    ///
    /// The mockup's third field, `FLIGHT TIME`, is deliberately absent — see the
    /// file comment.
    private func drawBottomRow(_ card: RecapJourneyCard, in rect: CGRect, surface: RenderSurface) {
        let tokens = style.journeyCard
        let scale = surface.scale
        let labelY = rect.minY + rect.height * 0.60
        let valueY = rect.minY + rect.height * 0.16
        let distance = Self.distance(travelledM: card.distanceM)
            .map { "\($0.value) \($0.unit)" } ?? "—"

        drawField(
            icon: .plane, label: "DISTANCE", value: distance,
            left: rect.minX, rows: FieldRows(labelY: labelY, valueY: valueY), in: surface
        )
        // No dates is a real state, not a hole to fill: a trip whose photographs
        // carry no `taken_at` has none, and the pass prints what it knows.
        guard let range = Self.dateRange(card.dates) else { return }

        let separatorX = rect.minX + rect.width * 0.5
        surface.context.saveGState()
        surface.context.setStrokeColor(tokens.ruleColor)
        surface.context.setLineWidth(scale)
        surface.context.move(to: CGPoint(x: separatorX, y: rect.minY + rect.height * 0.12))
        surface.context.addLine(to: CGPoint(x: separatorX, y: rect.minY + rect.height * 0.88))
        surface.context.strokePath()
        surface.context.restoreGState()

        drawField(
            icon: .calendar, label: "DATE", value: range,
            left: separatorX + tokens.paddingPx * scale,
            rows: FieldRows(labelY: labelY, valueY: valueY), in: surface
        )
    }

    /// The two dates as one range, the way a ticket prints them. Both facts, one
    /// field — the arrangement is the mockup's, the content is unchanged.
    static func dateRange(_ dates: RecapTrip.CrossingDates?) -> String? {
        guard let dates else { return nil }
        return dates.departure == dates.arrival
            ? dates.departure
            : "\(dates.departure) – \(dates.arrival)"
    }

    /// The two baselines a bottom-row field is set on.
    struct FieldRows {
        let labelY: CGFloat
        let valueY: CGFloat
    }

    private func drawField(
        icon: CardIcon, label: String, value: String, left: CGFloat,
        rows: FieldRows, in surface: RenderSurface
    ) {
        let labelY = rows.labelY, valueY = rows.valueY
        let tokens = style.journeyCard
        let scale = surface.scale
        let side = tokens.valueFontPx * scale
        drawIcon(icon, in: CGRect(
            x: left, y: (labelY + valueY) / 2 - side * 0.35, width: side, height: side
        ), in: surface)
        let textX = left + side * 1.5
        drawText(
            label, at: CGPoint(x: textX, y: labelY), fontPx: tokens.labelFontPx,
            color: tokens.mutedColor, tracking: tokens.labelFontPx * tokens.labelTrackingEm * scale,
            in: surface
        )
        drawText(
            value, at: CGPoint(x: textX, y: valueY), fontPx: tokens.valueFontPx,
            color: tokens.inkColor, in: surface
        )
    }

}
