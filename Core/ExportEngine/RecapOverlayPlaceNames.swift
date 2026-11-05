import CoreGraphics
import Foundation

/// **The trip's own towns, named on the map** (Chiu 2026-10-02, ADR file
/// 2026-10-02): a dot on each town, and its name under it — under, because a
/// stop's own name stands above its pin (`drawStopLabel`), and a town is often
/// where a stop is.
extension RecapOverlayRenderer {
    /// One name, laid out: its lines, the box they fill and the town's point.
    struct PlacedName {
        let lines: [String]
        let rect: CGRect
        let point: CGPoint
    }

    func drawPlaceNames(_ names: [RecapPlaceName], opacity: Double, into surface: RenderSurface) {
        guard opacity > 0.001 else { return }
        let token = style.placeName, scale = surface.scale
        let context = surface.context
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(CGFloat(opacity))
        for (index, placed) in drawnNames(names, in: surface) {
            // The dot stays: the town is still there. Only its name yields.
            drawPin(at: placed.point, radius: token.dotRadiusPx * scale, in: surface)
            context.saveGState()
            defer { context.restoreGState() }
            context.setAlpha(CGFloat(opacity * names[index].opacity))
            // Under the name, so its halo cuts the ink away from the letters.
            drawPlaceInk(names[index].ink, name: names[index].name, around: placed.rect, in: surface)
            for (row, text) in placed.lines.enumerated() {
                let baselineY = placed.rect.maxY - token.fontPx * scale
                    - CGFloat(row) * token.fontPx * token.lineHeightEm * scale
                drawHaloedText(text, anchor: CGPoint(x: placed.rect.midX, y: baselineY), in: surface)
            }
        }
    }

    /// **Which names this frame draws, and where** — by name and place only:
    /// nothing here reads `opacity` or `ink`, so fading a name or inking a town
    /// never changes which names are drawn.
    ///
    /// Decided over every name, in or out of the frame: the dolly only
    /// translates, so which names survive does not change as it moves and none
    /// appears or disappears because another came into view.
    func drawnNames(_ names: [RecapPlaceName], in surface: RenderSurface) -> [(index: Int, placed: PlacedName)] {
        let placed = names.map { layout($0, in: surface) }
        let frame = CGRect(x: 0, y: 0, width: surface.widthPx, height: surface.heightPx)
        let clearance = Self.nameClearancePx(style.placeName) * surface.scale
        var drawn: [CGRect] = []
        var shown: [(index: Int, placed: PlacedName)] = []
        for index in Self.uncrowded(placed.map { $0.rect.insetBy(dx: -clearance, dy: -clearance) })
        where frame.contains(placed[index].point) {
            // A town near the edge keeps its whole name: the box slides inside
            // the frame — clear of the HUD above and the map credit below — and
            // gives way if that puts it on a name already drawn.
            let rect = Self.held(placed[index].rect, inside: nameBounds(in: surface))
            guard !drawn.contains(where: { $0.intersects(rect) }) else { continue }
            drawn.append(rect.insetBy(dx: -clearance, dy: -clearance))
            shown.append((index, PlacedName(lines: placed[index].lines, rect: rect, point: placed[index].point)))
        }
        return shown
    }

    /// The room every name keeps round itself: `clearancePx`, or more if the
    /// ink needs more (`inkReachPx`) — for every name, inked or not, from the
    /// first frame, so a town being inked never pushes a neighbour off the map.
    static func nameClearancePx(_ token: RecapPlaceNameStyle) -> CGFloat {
        max(token.clearancePx, inkReachPx(token))
    }

    /// Where a name may sit: the frame, less the room the names keep around
    /// themselves, the HUD's row at the top and the map credit's at the bottom.
    private func nameBounds(in surface: RenderSurface) -> CGRect {
        let scale = surface.scale, clearance = Self.nameClearancePx(style.placeName) * scale
        let hud = (style.hudMarginPx + style.hudFontPx + 2 * style.hudPillPaddingYPx) * scale
        let credit = (style.mapCredit.marginPx + style.mapCredit.fontPx + 2 * style.mapCredit.pillPaddingYPx) * scale
        return CGRect(
            x: clearance, y: credit + clearance, width: CGFloat(surface.widthPx) - 2 * clearance,
            height: CGFloat(surface.heightPx) - hud - credit - 2 * clearance
        )
    }

    /// Centred type in the name's ink over a halo: the glyphs stroked wide in
    /// the halo colour, then filled. `anchor` is (centre x, baseline y).
    private func drawHaloedText(_ text: String, anchor: CGPoint, in surface: RenderSurface) {
        let token = style.placeName, context = surface.context
        context.saveGState()
        context.setTextDrawingMode(.stroke)
        context.setLineWidth(2 * token.haloPx * surface.scale)
        context.setLineJoin(.round)
        context.setStrokeColor(token.haloColor)
        drawCenteredText(
            text, centerX: anchor.x, baselineY: anchor.y, fontPx: token.fontPx, color: token.haloColor, in: surface
        )
        context.setTextDrawingMode(.fill)
        drawCenteredText(
            text, centerX: anchor.x, baselineY: anchor.y, fontPx: token.fontPx, color: token.textColor, in: surface
        )
        context.restoreGState()
    }

    /// `rect` moved the least that puts it inside `bounds`; unmoved when it is
    /// inside already, and pinned to the low edge when it cannot fit.
    static func held(_ rect: CGRect, inside bounds: CGRect) -> CGRect {
        let originX = max(min(rect.minX, bounds.maxX - rect.width), bounds.minX)
        let originY = max(min(rect.minY, bounds.maxY - rect.height), bounds.minY)
        return CGRect(x: originX, y: originY, width: rect.width, height: rect.height)
    }

    private func layout(_ name: RecapPlaceName, in surface: RenderSurface) -> PlacedName {
        let token = style.placeName, scale = surface.scale
        let point = surface.cgPoint(lat: name.coordinate.lat, lon: name.coordinate.lon)
        let lines = Self.lines(of: name.name, maxWidth: token.maxWidthPx * scale) {
            textWidth($0, fontPx: token.fontPx, in: surface)
        }
        let width = lines.map { textWidth($0, fontPx: token.fontPx, in: surface) }.max() ?? 0
        let height = token.fontPx * scale * (1 + CGFloat(lines.count - 1) * token.lineHeightEm)
        let top = point.y - (token.dotRadiusPx + token.dotGapPx) * scale
        return PlacedName(
            lines: lines, rect: CGRect(x: point.x - width / 2, y: top - height, width: width, height: height),
            point: point
        )
    }

    /// The rects that can all be drawn without touching, taken in order: each
    /// is kept unless it meets one already kept. So the order is the priority.
    static func uncrowded(_ rects: [CGRect]) -> [Int] {
        var kept: [Int] = []
        for (index, rect) in rects.enumerated() where !kept.contains(where: { rects[$0].intersects(rect) }) {
            kept.append(index)
        }
        return kept
    }

    /// A name on one line, or — when it is wider than `maxWidth` and has words
    /// to break between — on the two lines that are nearest in width.
    static func lines(of name: String, maxWidth: CGFloat, width: (String) -> CGFloat) -> [String] {
        let words = name.split(separator: " ").map(String.init)
        guard words.count > 1, width(name) > maxWidth else { return [name] }
        let breaks = (1..<words.count).map { split in
            [words[..<split].joined(separator: " "), words[split...].joined(separator: " ")]
        }
        return breaks.min { lhs, rhs in
            (lhs.map(width).max() ?? 0) < (rhs.map(width).max() ?? 0)
        } ?? [name]
    }
}
