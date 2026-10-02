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
        let placed = names.map { layout($0, in: surface) }
        let frame = CGRect(x: 0, y: 0, width: surface.widthPx, height: surface.heightPx)
        let context = surface.context
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(CGFloat(opacity))
        // Decided over every name, in or out of the frame: the dolly only
        // translates, so which names survive does not change as it moves and
        // none appears or disappears because another came into view.
        let clearance = token.clearancePx * scale
        var drawn: [CGRect] = []
        for index in Self.uncrowded(placed.map { $0.rect.insetBy(dx: -clearance, dy: -clearance) })
        where frame.contains(placed[index].point) {
            // A town near the edge keeps its whole name: the box slides inside
            // the frame, and gives way if that puts it on a name already drawn.
            let rect = Self.held(placed[index].rect, inside: frame.insetBy(dx: clearance, dy: clearance))
            guard !drawn.contains(where: { $0.intersects(rect) }) else { continue }
            drawn.append(rect.insetBy(dx: -clearance, dy: -clearance))
            drawPin(at: placed[index].point, radius: token.dotRadiusPx * scale, in: surface)
            for (row, text) in placed[index].lines.enumerated() {
                let baselineY = rect.maxY - token.fontPx * scale
                    - CGFloat(row) * token.fontPx * token.lineHeightEm * scale
                drawShadowedText(
                    text, anchor: CGPoint(x: rect.midX, y: baselineY), fontPx: token.fontPx,
                    tracking: 0, color: style.labelTextColor, in: surface
                )
            }
        }
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
