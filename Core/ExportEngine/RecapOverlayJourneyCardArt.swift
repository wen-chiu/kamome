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

    /// The card stock: rounded, shadowed, opaque enough to be a printed object
    /// rather than a translucent panel, with a notch bitten out of each **outer
    /// edge**.
    ///
    /// 🔴 **Outer edges, not the tear line** (Chiu 2026-09-04, from the film).
    /// They were on the tear line, top and bottom, and a hole in the middle of a
    /// card reads as a *disc* — Chiu saw exactly that, "下半藍上半白色各半圓形",
    /// because whatever the map happened to be showing filled each circle. On the
    /// outer edge the same hole reads as a ticket, which is what the reference
    /// draws.
    ///
    /// 🔴 They are holes in a single even-odd path, not a second pass with
    /// `.destinationOut`. That was the first attempt and it cut through the *map*:
    /// `destinationOut` erases whatever is already in the context, and by this
    /// point that is the frame. One compound path can only remove the stock,
    /// which is the whole of what a notch is.
    func drawStock(_ rect: CGRect, tearX: CGFloat, in surface: RenderSurface) {
        let tokens = style.journeyCard
        let context = surface.context
        let corner = tokens.cornerPx * surface.scale
        let radius = tokens.notchRadiusPx * surface.scale
        let outline = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

        // **The shadow is its own pass, and it is clipped to OUTSIDE the card.**
        // Drawn with the stock, it fell *under the notches* and showed through
        // them as a dark half-disc — half of the "半深半白" Chiu saw. Clipping a
        // huge rect against the outline with even-odd leaves only the region
        // beyond the card, so the shadow can reach the map and never the holes.
        context.saveGState()
        let beyond = CGMutablePath()
        beyond.addRect(rect.insetBy(dx: -rect.width, dy: -rect.height))
        beyond.addPath(outline)
        context.addPath(beyond)
        context.clip(using: .evenOdd)
        context.setShadow(
            offset: CGSize(width: 0, height: -tokens.shadowOffsetPx * surface.scale),
            blur: tokens.shadowBlurPx * surface.scale, color: tokens.shadowColor
        )
        context.setFillColor(tokens.stockColor)
        context.addPath(outline)
        context.fillPath()
        context.restoreGState()

        // **The stock is clipped to the card before it is filled.** Each notch's
        // centre sits *on* an edge, so half its circle lies outside the outline —
        // and out there the even-odd rule counts one crossing, calls it inside,
        // and fills it. That was the white half-disc bulging past the card, the
        // other half of what Chiu saw. Clipped, only the inner half can paint,
        // and the even-odd rule turns it into the hole it is meant to be.
        let stock = CGMutablePath()
        stock.addPath(outline)
        for centerX in [rect.minX, rect.maxX] {
            stock.addEllipse(in: CGRect(
                x: centerX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2
            ))
        }
        context.saveGState()
        context.addPath(outline)
        context.clip()
        context.setFillColor(tokens.stockColor)
        context.addPath(stock)
        context.fillPath(using: .evenOdd)
        context.restoreGState()
    }

    /// The tear line — dashed, full height, and uninterrupted since the notches
    /// moved to the outer edges (Chiu 2026-09-04: he likes the dashes).
    func drawPerforation(atX tearX: CGFloat, in rect: CGRect, surface: RenderSurface) {
        let tokens = style.journeyCard
        let context = surface.context
        let scale = surface.scale
        let inset = tokens.cornerPx * scale * 0.5

        context.saveGState()
        context.setStrokeColor(tokens.ruleColor)
        context.setLineWidth(tokens.arcWidthPx * scale * 0.8)
        context.setLineDash(phase: 0, lengths: [
            tokens.perforationDashPx * scale, tokens.perforationGapPx * scale
        ])
        context.move(to: CGPoint(x: tearX, y: rect.minY + inset))
        context.addLine(to: CGPoint(x: tearX, y: rect.maxY - inset))
        context.strokePath()
        context.restoreGState()
    }

    /// **A decorative barcode on the stub** (Chiu 2026-09-04).
    ///
    /// 🔴 **It encodes nothing, and it must never encode anything.** The bar
    /// widths come from a fixed integer sequence in this function, not from the
    /// trip, the share URL or any other payload. Same reasoning as PD-4's refusal
    /// to draw a QR on the end card: a code that invites a scan and resolves to
    /// nothing is worse than no code — and one that *did* carry a real payload
    /// would put trip data on a shareable frame, which is a §0 decision nobody has
    /// made. This is ticket furniture, the visual equivalent of the perforation.
    func drawBarcode(in rect: CGRect, in surface: RenderSurface) {
        let tokens = style.journeyCard
        guard rect.width > 0, rect.height > 0 else { return }
        let context = surface.context
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(tokens.barcodeColor)
        // A fixed pattern: deliberately not derived, so no future reader can
        // mistake it for data and no future edit can make it carry any.
        let widths: [CGFloat] = [1, 2, 1, 3, 1, 1, 2, 1, 1, 3, 2, 1, 1, 2, 3, 1, 1, 1, 2, 1]
        let unit = rect.width / widths.reduce(0, +) / 2
        var barX = rect.minX
        for (index, weight) in widths.enumerated() {
            let barWidth = weight * unit
            if index % 2 == 0 {
                context.fill(CGRect(x: barX, y: rect.minY, width: barWidth, height: rect.height))
            }
            barX += barWidth * 2
        }
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
    func drawFlightEnds(
        origin: RecapFlightEnd?, destination: RecapFlightEnd, opacity: Double,
        into surface: RenderSurface
    ) {
        guard opacity > 0.001 else { return }
        let context = surface.context
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(CGFloat(opacity))
        let side = style.flightEnd.markLengthPx * surface.scale
        for end in [origin, destination].compactMap({ $0 }) {
            let at = surface.cgPoint(lat: end.coordinate.lat, lon: end.coordinate.lon)
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
