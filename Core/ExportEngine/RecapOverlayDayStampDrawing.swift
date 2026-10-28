import CoreGraphics
import Foundation

/// **The day stamp** (Chiu 2026-10-28, ADR 2026-10-28-a-new-day-presses-a-stamp-into-the-film):
/// a hand-pressed ink stamp naming the new day, which then flies into the HUD
/// pill's day slot and becomes the HUD's own type. Tokens: `RecapDayStampStyle`.
///
/// It presses, holds and lands (`RecapDayStamp.press`, `.land`). Landing, the
/// border and the gull lift away, the day shrinks to the pill's size, turns
/// upright and takes the HUD's colour, so that at the end it is drawn exactly
/// where and as the HUD draws its day — the hand-off has no seam.
///
/// Everything here is deterministic: the border's wobble and the ink's gaps come
/// from the day's own text through FNV-1a, never from `Hasher` or a random source,
/// so a film's frames are byte-identical run to run and each day's stamp is a
/// little different from the last.
extension RecapOverlayRenderer {
    func drawDayStamp(_ stamp: RecapDayStamp, landingIn line: HUDLine, into surface: RenderSurface) {
        let tokens = style.dayStamp
        let scale = surface.scale
        let land = Self.ease(stamp.land)
        let pressScale = Self.pressScale(stamp.press, tokens: tokens)
        let inkAlpha = Self.ease(stamp.press / 0.4)
        guard inkAlpha > 0.001 else { return }

        // The day's size runs from the stamp's to the pill's.
        let fontPx = tokens.fontPx + (line.fontPx - tokens.fontPx) * land
        let tracking = fontPx * tokens.trackingEm * (1 - land) * scale
        let dayWidth = textWidth(stamp.label, fontPx: fontPx, tracking: tracking, in: surface)
        let box = stampBox(textWidthPx: dayWidth, fontPx: fontPx, in: surface)

        let pressed = pressCentre(box: stampBox(
            textWidthPx: textWidth(
                stamp.label, fontPx: tokens.fontPx, tracking: tokens.fontPx * tokens.trackingEm * scale, in: surface
            ),
            fontPx: tokens.fontPx, in: surface
        ), line: line, in: surface)
        let slotWidth = textWidth(stamp.label, fontPx: line.fontPx, in: surface)
        let slot = CGPoint(x: line.origin.x + slotWidth / 2, y: line.origin.y + line.fontPx * tokens.textCentreEm * scale)
        let centre = CGPoint(x: pressed.x + (slot.x - pressed.x) * land, y: pressed.y + (slot.y - pressed.y) * land)

        let context = surface.context
        context.saveGState()
        context.setAlpha(CGFloat(inkAlpha))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.translateBy(x: centre.x, y: centre.y)
        context.rotate(by: tokens.rotationDeg * (1 - land) * .pi / 180)
        context.scaleBy(x: pressScale, y: pressScale)

        let seed = Self.fnv1a(stamp.label)
        let frameAlpha = 1 - Self.ease(stamp.land / 0.6)
        if frameAlpha > 0.001 {
            drawStampFrame(size: box, seed: seed, alpha: frameAlpha, in: surface)
        }
        let textColor = Self.mix(tokens.inkColor, style.hudTextColor, Self.ease((stamp.land - 0.3) / 0.7))
        drawText(
            stamp.label, at: CGPoint(x: -dayWidth / 2, y: -fontPx * tokens.textCentreEm * scale),
            fontPx: fontPx, color: textColor, tracking: tracking, in: surface
        )
        knockOutSpeckles(in: box, seed: seed, strength: 1 - land, in: surface)

        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// The stamp's outer size for a day of this width, centred on the origin.
    private func stampBox(textWidthPx: CGFloat, fontPx: CGFloat, in surface: RenderSurface) -> CGSize {
        let tokens = style.dayStamp
        let scale = surface.scale
        let ratio = fontPx / tokens.fontPx
        let inset = (tokens.innerInsetPx + tokens.outerLinePx) * scale * ratio
        return CGSize(
            width: textWidthPx + (tokens.paddingXPx * scale * ratio + inset) * 2,
            height: fontPx * 0.8 * scale + (tokens.paddingYPx * scale * ratio + inset) * 2
        )
    }

    /// Where the stamp presses, by `RecapDayStampStyle.position`.
    private func pressCentre(box: CGSize, line: HUDLine, in surface: RenderSurface) -> CGPoint {
        let tokens = style.dayStamp
        let scale = surface.scale
        switch tokens.position {
        case .underThePill:
            return CGPoint(
                x: line.pill.minX + tokens.underPillInsetPx * scale + box.width / 2,
                y: line.pill.minY - tokens.underPillGapPx * scale - box.height / 2
            )
        case .upperCentre:
            return CGPoint(
                x: CGFloat(surface.widthPx) / 2,
                y: CGFloat(surface.heightPx) * (1 - tokens.upperCentreFraction)
            )
        }
    }

    /// The double border, drawn by a hand that wanders a little, with the gull
    /// breaking the top edge.
    private func drawStampFrame(size: CGSize, seed: UInt64, alpha: CGFloat, in surface: RenderSurface) {
        let tokens = style.dayStamp
        let scale = surface.scale
        let context = surface.context
        let ink = tokens.inkColor.copy(alpha: alpha) ?? tokens.inkColor
        context.saveGState()
        context.setStrokeColor(ink)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        let outer = CGSize(width: size.width - tokens.outerLinePx * scale, height: size.height - tokens.outerLinePx * scale)
        context.setLineWidth(tokens.outerLinePx * scale)
        context.addPath(wobblyBorder(outer, seed: seed, in: surface))
        context.strokePath()
        let insetBy = (tokens.innerInsetPx + tokens.outerLinePx) * scale * 2
        let inner = CGSize(width: size.width - insetBy, height: size.height - insetBy)
        context.setLineWidth(tokens.innerLinePx * scale)
        context.addPath(wobblyBorder(inner, seed: seed &* 31 &+ 7, in: surface))
        context.strokePath()

        // The gap the gull sits in, then the gull.
        let mark = tokens.markLengthPx * scale
        let top = outer.height / 2
        context.setBlendMode(.destinationOut)
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: -mark * 0.7, y: top - mark * 0.45, width: mark * 1.4, height: mark * 0.9))
        context.setBlendMode(.normal)
        VehicleMarker.seagull.draw(
            in: context, at: CGPoint(x: 0, y: top), lengthPx: mark, rotationDegrees: 0,
            colors: VehicleMarker.Palette(fill: ink, accent: ink, outline: ink)
        )
        context.restoreGState()
    }

    /// A squared superellipse of this size whose radius wanders by up to
    /// `wobblePx`, on three slow waves whose phases come from `seed`.
    private func wobblyBorder(_ size: CGSize, seed: UInt64, in surface: RenderSurface) -> CGPath {
        let tokens = style.dayStamp
        let wobble = tokens.wobblePx * surface.scale
        let exponent = 2 / tokens.squareness
        let phases: [Double] = (0..<3).map { index in
            let bits = Double((seed >> UInt64(index * 16)) & 0xFFFF)
            return bits / 65_535 * 2 * Double.pi
        }
        let path = CGMutablePath()
        let steps = 180
        for step in 0..<steps {
            let theta = Double(step) / Double(steps) * 2 * Double.pi
            let cosT = cos(theta), sinT = sin(theta)
            let alongX = CGFloat(copysign(pow(abs(cosT), Double(exponent)), cosT)) * size.width / 2
            let alongY = CGFloat(copysign(pow(abs(sinT), Double(exponent)), sinT)) * size.height / 2
            let slow: Double = 0.55 * sin(3 * theta + phases[0])
            let quick: Double = 0.3 * sin(7 * theta + phases[1]) + 0.15 * sin(13 * theta + phases[2])
            let wander = wobble * CGFloat(slow + quick) / max(hypot(alongX, alongY), 1)
            let point = CGPoint(x: alongX + alongX * wander, y: alongY + alongY * wander)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Small gaps where the ink did not take, over the border and the day alike.
    /// `strength` fades them as the stamp becomes the HUD's clean type.
    private func knockOutSpeckles(in size: CGSize, seed: UInt64, strength: CGFloat, in surface: RenderSurface) {
        let tokens = style.dayStamp
        guard strength > 0.001, tokens.speckleCount > 0 else { return }
        let context = surface.context
        var state = seed | 1
        func next() -> CGFloat {
            // xorshift64: deterministic, and enough for where a speck falls.
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return CGFloat(state % 10_000) / 10_000
        }
        context.saveGState()
        context.setBlendMode(.destinationOut)
        for _ in 0..<tokens.speckleCount {
            let speckX = (next() - 0.5) * size.width
            let speckY = (next() - 0.5) * size.height
            let radius = (0.35 + 0.65 * next()) * tokens.speckleMaxRadiusPx * surface.scale
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: (0.45 + 0.5 * next()) * strength))
            context.fillEllipse(in: CGRect(x: speckX - radius, y: speckY - radius, width: radius * 2, height: radius * 1.6))
        }
        context.restoreGState()
    }

    /// Down a little past its size as it meets the page, then settled.
    private static func pressScale(_ press: Double, tokens: RecapDayStampStyle) -> CGFloat {
        let meets = 0.6
        if press < meets {
            let fall = press / meets
            return tokens.pressFromScale + (tokens.pressUndershootScale - tokens.pressFromScale) * CGFloat(fall * fall)
        }
        return tokens.pressUndershootScale + (1 - tokens.pressUndershootScale) * ease((press - meets) / (1 - meets))
    }

    static func ease(_ fraction: Double) -> CGFloat {
        let clamped = min(max(fraction, 0), 1)
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
    }

    /// Two sRGB colours, mixed.
    private static func mix(_ from: CGColor, _ toward: CGColor, _ amount: CGFloat) -> CGColor {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let lhs = from.converted(to: srgb, intent: .defaultIntent, options: nil)?.components,
              let rhs = toward.converted(to: srgb, intent: .defaultIntent, options: nil)?.components,
              lhs.count == 4, rhs.count == 4 else { return amount < 0.5 ? from : toward }
        let mixed = zip(lhs, rhs).map { $0 + ($1 - $0) * amount }
        return CGColor(srgbRed: mixed[0], green: mixed[1], blue: mixed[2], alpha: mixed[3])
    }

    /// FNV-1a over the day's UTF-8: stable across runs and processes.
    static func fnv1a(_ text: String) -> UInt64 {
        text.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
    }
}
