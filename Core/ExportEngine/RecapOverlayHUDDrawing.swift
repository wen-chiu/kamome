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
    func drawHUD(dayLabel: String, place: String?, travelledM: Double, into surface: RenderSurface) {
        let scale = surface.scale
        let margin = style.hudMarginPx * scale
        let padding = CGSize(width: style.hudPillPaddingXPx * scale, height: style.hudPillPaddingYPx * scale)
        let pillH = style.hudFontPx * scale + padding.height * 2
        let top = CGFloat(surface.heightPx) - margin
        let baselineY = top - padding.height - style.hudFontPx * scale * 0.82

        let badge = [dayLabel, place].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if !badge.isEmpty {
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
            drawPill(pill, in: surface)
            drawText(
                badge, at: CGPoint(x: pill.minX + padding.width, y: baselineY),
                fontPx: fitted, color: style.hudTextColor, in: surface
            )
        }

        guard let distance = Self.distance(travelledM: travelledM) else { return }
        drawDistance(distance, rightEdge: CGFloat(surface.widthPx) - margin, baselineY: baselineY, in: surface)
    }

    private func drawPill(_ rect: CGRect, in surface: RenderSurface) {
        let context = surface.context
        let corner = rect.height / 2
        let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        context.setFillColor(style.hudPillColor)
        context.addPath(path)
        context.fillPath()
        context.setStrokeColor(style.hudPillBorderColor)
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
