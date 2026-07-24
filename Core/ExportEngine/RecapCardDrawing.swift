import CoreGraphics
import CoreText
import Foundation

/// Overlay card drawing for §4.5 steps 3–4 — split from the frame/route
/// compositing purely to keep each file readable; same type, same render pass.
extension RecapFrameCompositor {
    /// Card anchored at the bottom of the frame: photo square on the left,
    /// stop name beside it, day badge on the card's top edge.
    func draw(card: StopCard, in context: CGContext) {
        let margin = style.cardMarginPx * scale
        let cardHeight = style.cardHeightPx * scale
        // CG space: y is measured from the bottom edge.
        let rect = CGRect(x: margin, y: margin, width: CGFloat(widthPx) - margin * 2, height: cardHeight)
        let corner = style.cardCornerPx * scale
        let padding = style.cardPaddingPx * scale

        context.setFillColor(style.cardColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.fillPath()

        var textX = rect.minX + padding
        if let photo = card.photo {
            let side = cardHeight - padding * 2
            let photoRect = CGRect(x: rect.minX + padding, y: rect.minY + padding, width: side, height: side)
            context.saveGState()
            context.addPath(
                CGPath(roundedRect: photoRect, cornerWidth: corner / 2, cornerHeight: corner / 2, transform: nil)
            )
            context.clip()
            context.draw(photo, in: photoRect)
            context.restoreGState()
            textX = photoRect.maxX + padding
        }

        if let detail = card.detail {
            // Two lines: name upper, kind detail (e.g. walking duration) lower.
            let gap = padding / 2
            let nameH = style.nameFontPx * scale
            let detailH = style.detailFontPx * scale
            let blockTop = rect.midY + (nameH + gap + detailH) / 2
            drawText(
                card.name,
                at: CGPoint(x: textX, y: blockTop - nameH),
                fontPx: style.nameFontPx,
                color: style.cardTextColor,
                in: context
            )
            drawText(
                detail,
                at: CGPoint(x: textX, y: blockTop - nameH - gap - detailH),
                fontPx: style.detailFontPx,
                color: style.cardDetailColor,
                in: context
            )
        } else {
            drawText(
                card.name,
                at: CGPoint(x: textX, y: rect.midY - style.nameFontPx * scale / 2),
                fontPx: style.nameFontPx,
                color: style.cardTextColor,
                in: context
            )
        }
        drawBadge(card.dayLabel, straddling: rect, padding: padding, in: context)
    }

    /// Day badge pill straddling the card's top edge, left-aligned.
    private func drawBadge(_ label: String, straddling rect: CGRect, padding: CGFloat, in context: CGContext) {
        let badgeHeight = style.badgeHeightPx * scale
        let badgeRect = CGRect(
            x: rect.minX + padding,
            y: rect.maxY - badgeHeight / 2,
            width: textWidth(label, fontPx: style.badgeFontPx, color: style.badgeTextColor) + padding * 2,
            height: badgeHeight
        )
        context.setFillColor(style.badgeColor)
        context.addPath(
            CGPath(
                roundedRect: badgeRect,
                cornerWidth: badgeHeight / 2,
                cornerHeight: badgeHeight / 2,
                transform: nil
            )
        )
        context.fillPath()
        drawText(
            label,
            at: CGPoint(x: badgeRect.minX + padding, y: badgeRect.midY - style.badgeFontPx * scale / 2.5),
            fontPx: style.badgeFontPx,
            color: style.badgeTextColor,
            in: context
        )
    }

    /// Title panel pinned under the top margin, mirroring the stop card's
    /// bottom anchor (§4.5 step 4).
    func draw(titleCard card: TitleCard, in context: CGContext) {
        let margin = style.cardMarginPx * scale
        let padding = style.cardPaddingPx * scale
        let titleHeight = style.titleFontPx * scale
        let subtitleHeight = style.subtitleFontPx * scale
        let panelHeight = padding * 2 + titleHeight + padding / 2 + subtitleHeight
        let rect = CGRect(
            x: margin,
            y: CGFloat(heightPx) - margin - panelHeight,
            width: CGFloat(widthPx) - margin * 2,
            height: panelHeight
        )
        fillPanel(rect, in: context)
        drawCenteredText(
            card.title,
            baselineY: rect.maxY - padding - titleHeight * 0.8,
            fontPx: style.titleFontPx,
            color: style.cardTextColor,
            in: context
        )
        drawCenteredText(
            card.subtitle,
            baselineY: rect.minY + padding,
            fontPx: style.subtitleFontPx,
            color: style.cardTextColor,
            in: context
        )
    }

    /// End panel centered on the frame: stat lines, then the "Get this
    /// route" QR, then the call to action (§4.5 step 4).
    func draw(endCard card: EndCard, in context: CGContext) {
        let margin = style.cardMarginPx * scale
        let padding = style.cardPaddingPx * scale
        let statLineHeight = style.statFontPx * scale * 1.4
        let qrSide = style.qrSidePx * scale
        let ctaHeight = style.subtitleFontPx * scale
        let panelHeight = padding * 2 + CGFloat(card.statsLines.count) * statLineHeight
            + padding / 2 + qrSide + padding / 2 + ctaHeight
        let rect = CGRect(
            x: margin,
            y: (CGFloat(heightPx) - panelHeight) / 2,
            width: CGFloat(widthPx) - margin * 2,
            height: panelHeight
        )
        fillPanel(rect, in: context)

        var baselineY = rect.maxY - padding - style.statFontPx * scale * 0.8
        for statLine in card.statsLines {
            drawCenteredText(statLine, baselineY: baselineY, fontPx: style.statFontPx, color: style.cardTextColor, in: context)
            baselineY -= statLineHeight
        }
        if let qrCode = card.qrCode {
            let qrRect = CGRect(
                x: rect.midX - qrSide / 2,
                y: rect.minY + padding + ctaHeight + padding / 2,
                width: qrSide,
                height: qrSide
            )
            // Nearest-neighbor keeps the QR modules scannable.
            context.saveGState()
            context.interpolationQuality = .none
            context.draw(qrCode, in: qrRect)
            context.restoreGState()
        }
        drawCenteredText(
            card.callToAction,
            baselineY: rect.minY + padding,
            fontPx: style.subtitleFontPx,
            color: style.cardTextColor,
            in: context
        )
    }

    private func fillPanel(_ rect: CGRect, in context: CGContext) {
        let corner = style.cardCornerPx * scale
        context.setFillColor(style.cardColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.fillPath()
    }

    private func drawCenteredText(
        _ text: String,
        baselineY: CGFloat,
        fontPx: CGFloat,
        color: CGColor,
        in context: CGContext
    ) {
        let lineWidth = textWidth(text, fontPx: fontPx, color: color)
        drawText(
            text,
            at: CGPoint(x: (CGFloat(widthPx) - lineWidth) / 2, y: baselineY),
            fontPx: fontPx,
            color: color,
            in: context
        )
    }

    private func font(px: CGFloat) -> CTFont {
        CTFontCreateWithName("HelveticaNeue-Bold" as CFString, px * scale, nil)
    }

    private func line(_ text: String, fontPx: CGFloat, color: CGColor) -> CTLine {
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font(px: fontPx),
            kCTForegroundColorAttributeName: color
        ]
        let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault,
            text as CFString,
            attributes as CFDictionary
        )
        // CFAttributedStringCreate only fails on allocation failure.
        return CTLineCreateWithAttributedString(attributed!)
    }

    private func textWidth(_ text: String, fontPx: CGFloat, color: CGColor) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text, fontPx: fontPx, color: color), nil, nil, nil))
    }

    private func drawText(_ text: String, at origin: CGPoint, fontPx: CGFloat, color: CGColor, in context: CGContext) {
        context.saveGState()
        context.textPosition = origin
        CTLineDraw(line(text, fontPx: fontPx, color: color), context)
        context.restoreGState()
    }
}
