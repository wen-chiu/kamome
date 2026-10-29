import CoreGraphics
import Foundation

/// **A reached town's ink** (Chiu 2026-10-29, ADR
/// 2026-10-29-the-film-inks-each-town-the-car-reaches): the mark someone makes
/// round a place on a paper road map. Tokens: `RecapPlaceNameStyle`'s `ink…`.
///
/// Round the **name**, never the dot: the car parks on the dot (`dotGapPx`), so
/// a ring there would be under it the moment it was drawn. The stroke goes down
/// along its length as a pen does, thin where the pen touches down and where it
/// lifts, and the loop runs on past its start and drifts outward, so it stays
/// open where the pen lifted. It is drawn under the name's halo, which cuts it
/// away wherever it passes a letter.
///
/// Deterministic: each mark's wander comes from its town's name through FNV-1a
/// and xorshift (ported from the day stamp of #334, whose concept Chiu
/// rejected), never from `Hasher` or a random source — so each town's loop
/// differs from the next, and every frame is byte-identical run to run.
extension RecapOverlayRenderer {
    /// One point of the pen's path, and half the stroke's width there.
    struct InkSample: Equatable {
        let point: CGPoint
        let halfWidth: CGFloat
    }

    /// `ink` of the town's mark (0…1, `RecapPlaceName.ink`) round a name set
    /// in `rect`, in the context's current alpha.
    func drawPlaceInk(_ ink: Double, name: String, around rect: CGRect, in surface: RenderSurface) {
        guard ink > 0.001 else { return }
        let token = style.placeName
        let shown = Self.penDown(
            Self.inkPath(name: name, around: rect, token: token, scale: surface.scale),
            fraction: Self.penPace(ink)
        )
        guard let first = shown.first, let last = shown.last, shown.count > 1 else { return }
        let context = surface.context
        // One layer, so the ink is one coat where the loop crosses itself and
        // where its ends are rounded off, whatever alpha it is faded by.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setFillColor(token.inkColor)
        context.addPath(Self.ribbon(shown))
        context.fillPath()
        for end in [first, last] {
            context.fillEllipse(in: CGRect(
                x: end.point.x - end.halfWidth, y: end.point.y - end.halfWidth,
                width: 2 * end.halfWidth, height: 2 * end.halfWidth
            ))
        }
        context.endTransparencyLayer()
    }

    /// How far past a name's box its ink can reach, at the 1080 reference — on
    /// its widest side. `drawPlaceNames` keeps at least this much room round
    /// every name, inked or not, so the ink never changes which names are drawn.
    static func inkReachPx(_ token: RecapPlaceNameStyle) -> CGFloat {
        let stroke = token.inkWobblePx + token.inkStrokePx / 2
        let below = token.inkGlyphBottomEm * token.fontPx
        switch token.inkMark {
        case .loop:
            let out = token.inkPaddingPx + token.inkSpiralPx / 2 + stroke
            // The lean moves the loop up and down, never sideways, and the pen
            // lifts straight up, so only the top has the lift.
            let above = out + token.inkTiltPx + token.inkLiftPx - (1 - token.inkGlyphTopEm) * token.fontPx
            return max(below + out + token.inkTiltPx, above, out)
        case .underline:
            return max(below + token.inkUnderlineGapPx + stroke, token.inkPaddingPx + token.inkStrokePx / 2)
        }
    }

    /// The whole of the pen's path for this name, before any of it is down.
    static func inkPath(name: String, around rect: CGRect, token: RecapPlaceNameStyle, scale: CGFloat) -> [InkSample] {
        let fontPx = token.fontPx * scale
        // The letters, not the box: capitals stop below its top, descenders
        // go below its bottom (`inkGlyphTopEm`).
        let top = rect.maxY - (1 - token.inkGlyphTopEm) * fontPx
        let bottom = rect.minY - token.inkGlyphBottomEm * fontPx
        let glyphs = CGRect(x: rect.minX, y: bottom, width: rect.width, height: max(top - bottom, 1))
        let dice = inkDice(fnv1a(name), count: 5)
        switch token.inkMark {
        case .loop: return loopPath(round: glyphs, dice: dice, token: token, scale: scale)
        case .underline: return underlinePath(under: glyphs, dice: dice, token: token, scale: scale)
        }
    }

    /// A loop round `box`: a rounded rectangle walked counter-clockwise from
    /// near the right end of its top edge, once round and on past the start.
    private static func loopPath(
        round box: CGRect, dice: [CGFloat], token: RecapPlaceNameStyle, scale: CGFloat
    ) -> [InkSample] {
        let pad = token.inkPaddingPx * scale
        let shape = InkLoop(halfWidth: box.width / 2 + pad, halfHeight: box.height / 2 + pad, pad: pad)
        // Touch down in the top edge's right quarter.
        let startS = shape.topEdge * 0.25 * dice[0]
        // The overrun stays on the top edge and the first half of the top-left
        // corner, so the pen lifting straight up lifts it off the loop.
        let overlap = min(token.inkOverlapPx * scale * (0.8 + 0.4 * dice[1]), shape.topEdge + shape.quarter / 2 - startS)
        let total = shape.perimeter + overlap
        let liftFrom = 1 - overlap / total
        let wobble = token.inkWobblePx * scale, spiral = token.inkSpiralPx * scale
        let lean = token.inkTiltPx * scale * (0.5 + 0.5 * dice[4])
        let phases = (dice[2] * 2 * .pi, dice[3] * 2 * .pi)
        return samples(along: total, scale: scale, liftLength: overlap * 0.6, token: token) { length, fraction in
            let (point, normal) = shape.point(at: startS + length)
            let turn = length / shape.perimeter * 2 * .pi
            // Slow: once and twice round, so the loop is lopsided, not shaky.
            let wander = wobble * (0.65 * sin(turn + phases.0) + 0.35 * sin(2 * turn + phases.1))
            let lift = fraction > liftFrom ? token.inkLiftPx * scale * pow((fraction - liftFrom) / (1 - liftFrom), 1.6) : 0
            let offset = spiral * (fraction - 0.5) + wander
            let along = min(max(point.x / shape.halfWidth, -1), 1)
            return CGPoint(
                x: box.midX + point.x + normal.x * offset, y: box.midY + point.y + normal.y * offset + lean * along + lift
            )
        }
    }

    /// A line under `box`, left to right, rising a little as a hand does.
    private static func underlinePath(
        under box: CGRect, dice: [CGFloat], token: RecapPlaceNameStyle, scale: CGFloat
    ) -> [InkSample] {
        let pad = token.inkPaddingPx * scale
        let startX = box.minX - pad / 2, total = box.width + pad * 1.5
        let baseY = box.minY - token.inkUnderlineGapPx * scale
        let wobble = token.inkWobblePx * scale, rise = token.inkUnderlineRisePx * scale
        let phases = (dice[2] * 2 * .pi, dice[3] * 2 * .pi)
        return samples(along: total, scale: scale, liftLength: pad * 1.5, token: token) { length, fraction in
            let wave = 0.6 * sin(fraction * 1.5 * .pi + phases.0) + 0.4 * sin(fraction * 3.5 * .pi + phases.1)
            return CGPoint(x: startX + length, y: baseY + rise * fraction + wobble * wave)
        }
    }

    /// The pen's path sampled every two reference pixels, `point(length,
    /// fraction)` giving where the pen is, with its pressure: lighter as it
    /// touches down and over `liftLength` as it lifts.
    private static func samples(
        along total: CGFloat, scale: CGFloat, liftLength: CGFloat, token: RecapPlaceNameStyle,
        point: (CGFloat, CGFloat) -> CGPoint
    ) -> [InkSample] {
        let count = max(Int(total / (2 * scale)), 2)
        let touch = 12 * scale
        return (0...count).map { index in
            let fraction = CGFloat(index) / CGFloat(count), length = fraction * total
            let pressure = (0.4 + 0.6 * ease(length / touch)) * (0.35 + 0.65 * ease((total - length) / max(liftLength, 1)))
            return InkSample(point: point(length, fraction), halfWidth: token.inkStrokePx * scale / 2 * pressure)
        }
    }

    /// The part of the path the pen has drawn by `fraction` of its time.
    static func penDown(_ path: [InkSample], fraction: CGFloat) -> [InkSample] {
        guard path.count > 1, fraction > 0 else { return [] }
        let reach = min(fraction, 1) * CGFloat(path.count - 1)
        let whole = Int(reach)
        var drawn = Array(path[...whole])
        let part = reach - CGFloat(whole)
        if part > 0.001, whole + 1 < path.count {
            let from = path[whole], toward = path[whole + 1]
            drawn.append(InkSample(
                point: CGPoint(x: from.point.x + (toward.point.x - from.point.x) * part,
                               y: from.point.y + (toward.point.y - from.point.y) * part),
                halfWidth: from.halfWidth + (toward.halfWidth - from.halfWidth) * part
            ))
        }
        return drawn
    }

    /// A pen goes round quickly and slows as it comes back to where it began.
    static func penPace(_ ink: Double) -> CGFloat {
        let time = CGFloat(min(max(ink, 0), 1))
        return 1 - (1 - time) * (1 - time)
    }

    /// The stroke's outline: one side out along the path, the other back.
    private static func ribbon(_ path: [InkSample]) -> CGPath {
        var left: [CGPoint] = [], right: [CGPoint] = []
        for index in path.indices {
            let before = path[max(index - 1, 0)].point, after = path[min(index + 1, path.count - 1)].point
            let length = max(hypot(after.x - before.x, after.y - before.y), 1e-6)
            let normal = CGPoint(x: -(after.y - before.y) / length, y: (after.x - before.x) / length)
            let (point, half) = (path[index].point, path[index].halfWidth)
            left.append(CGPoint(x: point.x + normal.x * half, y: point.y + normal.y * half))
            right.append(CGPoint(x: point.x - normal.x * half, y: point.y - normal.y * half))
        }
        let outline = CGMutablePath()
        outline.addLines(between: left + right.reversed())
        outline.closeSubpath()
        return outline
    }

    private static func ease(_ fraction: CGFloat) -> CGFloat {
        let clamped = min(max(fraction, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// `count` values in 0…1 from `seed` — xorshift64, as the day stamp's ink
    /// specks were placed.
    static func inkDice(_ seed: UInt64, count: Int) -> [CGFloat] {
        var state = seed | 1
        return (0..<count).map { _ in
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return CGFloat(state % 10_000) / 10_000
        }
    }

    /// FNV-1a over the name's UTF-8: stable across runs and processes.
    static func fnv1a(_ text: String) -> UInt64 {
        text.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
    }
}

/// The loop's line before the hand wanders off it: a rounded rectangle centred
/// on the origin, walked counter-clockwise from the right end of its top edge.
struct InkLoop {
    let halfWidth: CGFloat
    let halfHeight: CGFloat
    /// Round enough to read as drawn, square enough to keep the letters'
    /// corners inside: a corner of radius r stays clear of the box's corner
    /// while r ≤ pad·√2/(√2−1), about 3.4 pads.
    let radius: CGFloat

    init(halfWidth: CGFloat, halfHeight: CGFloat, pad: CGFloat) {
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        radius = min(halfWidth, halfHeight, 3 * pad)
    }

    var topEdge: CGFloat { 2 * (halfWidth - radius) }
    var sideEdge: CGFloat { 2 * (halfHeight - radius) }
    var quarter: CGFloat { .pi * radius / 2 }
    var perimeter: CGFloat { 2 * topEdge + 2 * sideEdge + 4 * quarter }

    /// The point `length` along the walk, and the outward normal there.
    func point(at length: CGFloat) -> (point: CGPoint, normal: CGPoint) {
        var along = length.truncatingRemainder(dividingBy: perimeter)
        if along < 0 { along += perimeter }
        let (width, height, corner) = (halfWidth, halfHeight, radius)
        if along < topEdge { return (CGPoint(x: width - corner - along, y: height), CGPoint(x: 0, y: 1)) }
        along -= topEdge
        if along < quarter { return arc(CGPoint(x: -width + corner, y: height - corner), from: .pi / 2, along) }
        along -= quarter
        if along < sideEdge { return (CGPoint(x: -width, y: height - corner - along), CGPoint(x: -1, y: 0)) }
        along -= sideEdge
        if along < quarter { return arc(CGPoint(x: -width + corner, y: -height + corner), from: .pi, along) }
        along -= quarter
        if along < topEdge { return (CGPoint(x: -width + corner + along, y: -height), CGPoint(x: 0, y: -1)) }
        along -= topEdge
        if along < quarter { return arc(CGPoint(x: width - corner, y: -height + corner), from: 1.5 * .pi, along) }
        along -= quarter
        if along < sideEdge { return (CGPoint(x: width, y: -height + corner + along), CGPoint(x: 1, y: 0)) }
        along -= sideEdge
        return arc(CGPoint(x: width - corner, y: height - corner), from: 0, along)
    }

    private func arc(_ centre: CGPoint, from angle: CGFloat, _ length: CGFloat) -> (point: CGPoint, normal: CGPoint) {
        let theta = angle + (radius > 0 ? length / radius : 0)
        let normal = CGPoint(x: cos(theta), y: sin(theta))
        return (CGPoint(x: centre.x + normal.x * radius, y: centre.y + normal.y * radius), normal)
    }
}
