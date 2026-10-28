import CoreGraphics
import Foundation

/// The film's persistent HUD — where we are in the trip, in the frame's top
/// corners, for the whole body of the film (Chiu 2026-07-31).
///
/// Ported from the prototype's `.hud` (`Docs/prototype/recap_engine.html`): a
/// dark translucent pill on the left carrying the day and, when the journey is
/// parked, the place; the running distance opposite it on the right with its unit
/// set back in the muted grey.
///
/// It used to be attached to the photo card, which meant the two numbers a viewer
/// most wants — *what day is this* and *how far have we come* — appeared for a few
/// seconds at each stop and vanished on the road in between, and the distance
/// looked like a property of the stop rather than of the journey. Anchoring it to
/// the frame instead makes it what it always was: chrome that answers those two
/// questions at any instant you pause the film.
extension RecapOverlayRenderer {
    /// The pill's line, laid out: what both the pill and a day stamp landing in
    /// its day slot are placed by, so the two can never disagree about where the
    /// day is.
    struct HUDLine {
        let pill: CGRect
        let fontPx: CGFloat
        /// The left end of the line's baseline — where the day starts.
        let origin: CGPoint
    }

    func drawHUD(
        dayLabel: String, place: String?, travelledM: Double, dayStamp: RecapDayStamp? = nil,
        into surface: RenderSurface
    ) {
        if let dayStamp {
            drawHUDBadge(stamping: dayStamp, place: place, into: surface)
        } else if let line = hudLine(day: dayLabel, place: place, in: surface) {
            drawPill(line.pill, fill: style.hudPillColor, border: style.hudPillBorderColor, in: surface)
            drawText(
                Self.badge(day: dayLabel, place: place), at: line.origin,
                fontPx: line.fontPx, color: style.hudTextColor, in: surface
            )
        }

        guard let distance = Self.distance(travelledM: travelledM) else { return }
        let baselineY = hudBaselineY(in: surface)
        drawDistance(
            distance, rightEdge: CGFloat(surface.widthPx) - style.hudMarginPx * surface.scale,
            baselineY: baselineY, in: surface
        )
    }

    /// The pill while a day is stamped in: the previous day fading, then the
    /// slot empty under the stamp until it lands (`RecapDayStamp`). The day and
    /// the rest of the line are set as two runs, so the day alone can fade.
    private func drawHUDBadge(stamping stamp: RecapDayStamp, place: String?, into surface: RenderSurface) {
        let clearing = stamp.clear < 1
        let day = clearing ? stamp.previousLabel : stamp.label
        guard let line = hudLine(day: day, place: place, in: surface) else { return }
        drawPill(line.pill, fill: style.hudPillColor, border: style.hudPillBorderColor, in: surface)
        if clearing, let faded = style.hudTextColor.copy(alpha: 1 - RecapOverlayRenderer.ease(stamp.clear)) {
            drawText(day, at: line.origin, fontPx: line.fontPx, color: faded, in: surface)
        }
        let rest = String(Self.badge(day: day, place: place).dropFirst(day.count))
        if !rest.isEmpty {
            let restX = line.origin.x + textWidth(day, fontPx: line.fontPx, in: surface)
            drawText(rest, at: CGPoint(x: restX, y: line.origin.y), fontPx: line.fontPx, color: style.hudTextColor, in: surface)
        }
        if !clearing { drawDayStamp(stamp, landingIn: line, into: surface) }
    }

    /// "Day 3 · 小樽運河": the day and the place, whichever are there.
    static func badge(day: String, place: String?) -> String {
        [day, place].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The pill's line for this day and place, or nil when it has nothing to say.
    func hudLine(day: String, place: String?, in surface: RenderSurface) -> HUDLine? {
        let badge = Self.badge(day: day, place: place)
        guard !badge.isEmpty else { return nil }
        let scale = surface.scale
        let margin = style.hudMarginPx * scale
        let padding = CGSize(width: style.hudPillPaddingXPx * scale, height: style.hudPillPaddingYPx * scale)
        let pillH = style.hudFontPx * scale + padding.height * 2
        let top = CGFloat(surface.heightPx) - margin
        // The place name is trip data of any length, so the badge shrinks to
        // fit its half of the row rather than running under the distance.
        let fitted = fittedFontPx(
            badge, preferred: style.hudFontPx,
            maxWidth: CGFloat(surface.widthPx) * 0.62 - padding.width * 2, in: surface
        )
        let pill = CGRect(
            x: margin, y: top - pillH,
            width: textWidth(badge, fontPx: fitted, in: surface) + padding.width * 2, height: pillH
        )
        return HUDLine(
            pill: pill, fontPx: fitted, origin: CGPoint(x: pill.minX + padding.width, y: hudBaselineY(in: surface))
        )
    }

    private func hudBaselineY(in surface: RenderSurface) -> CGFloat {
        let scale = surface.scale
        let top = CGFloat(surface.heightPx) - style.hudMarginPx * scale
        return top - style.hudPillPaddingYPx * scale - style.hudFontPx * scale * 0.82
    }

    /// The dark translucent plate that keeps unplated type legible over an
    /// arbitrary photograph. Its colours are arguments rather than read from
    /// `style.hud…` since 2026-09-12, so the map credit can wear the same idiom
    /// without inheriting the HUD's palette — one pill shape, two callers.
    func drawPill(
        _ rect: CGRect, fill: CGColor, border: CGColor, cornerRadius: CGFloat? = nil, in surface: RenderSurface
    ) {
        let context = surface.context
        let corner = cornerRadius ?? rect.height / 2
        let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        context.setFillColor(fill)
        context.addPath(path)
        context.fillPath()
        context.setStrokeColor(border)
        context.setLineWidth(style.hudPillBorderPx * surface.scale)
        context.addPath(path)
        context.strokePath()
    }

    /// "925 km", right-aligned: the number at the row's size, the unit smaller and
    /// muted (`.hud .km small`), so the figure reads at a glance and the unit does
    /// not compete with it.
    private func drawDistance(
        _ distance: (value: String, unit: String), rightEdge: CGFloat, baselineY: CGFloat, in surface: RenderSurface
    ) {
        let valuePx = style.hudFontPx
        let unitPx = valuePx * 0.8
        let gap = 8 * surface.scale
        let valueW = textWidth(distance.value, fontPx: valuePx, in: surface)
        let unitW = textWidth(distance.unit, fontPx: unitPx, in: surface)
        let originX = rightEdge - (valueW + gap + unitW)
        drawText(
            distance.value, at: CGPoint(x: originX, y: baselineY),
            fontPx: valuePx, color: style.hudTextColor, in: surface
        )
        drawText(
            distance.unit, at: CGPoint(x: originX + valueW + gap, y: baselineY),
            fontPx: unitPx, color: style.hudUnitColor, in: surface
        )
    }
}
