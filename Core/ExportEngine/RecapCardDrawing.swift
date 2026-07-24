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
        if let photo = card.photos.first {
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

    /// The photo deck (§5, Chiu 2026-07-23): at each stop the photo blooms —
    /// grows to a prominent size, rotates through the stop's 3–8 photos at
    /// `deck.photoHoldS` each with a progress-dots indicator (highlight leads),
    /// then shrinks back to the map. Modeled as a scale envelope over the hold
    /// `window`, so it is deterministic (fixed order + timing) for golden frames
    /// and robust to a hold squeezed by `max_hold_fraction` — the zoom clamps to
    /// the window and every photo still gets a slot.
    func drawDeck(card: StopCard, window: (startS: Double, endS: Double), atTime time: Double, in context: CGContext) {
        let photos = card.photos
        guard !photos.isEmpty else { return }
        let count = photos.count
        let length = max(window.endS - window.startS, 1e-6)
        // Grow-in / shrink-out never eat more than 80% of the window.
        let zoom = min(deck.zoomS, length * 0.4)
        let growEnd = window.startS + zoom
        let shrinkStart = window.endS - zoom

        let scaleValue: CGFloat
        if zoom > 0, time < growEnd {
            scaleValue = smoothstepFraction((time - window.startS) / zoom)
        } else if zoom > 0, time > shrinkStart {
            scaleValue = smoothstepFraction((window.endS - time) / zoom)
        } else {
            scaleValue = 1
        }
        guard scaleValue > 0.001 else { return }

        let rotateLen = max(shrinkStart - growEnd, 1e-6)
        let slot = rotateLen / Double(count)
        let index = min(max(Int((time - growEnd) / slot), 0), count - 1)

        // Peak layout, centered a touch above the middle so the caption + dots
        // sit below without leaving the frame.
        let peakW = CGFloat(widthPx) * style.deckPhotoWidthFraction
        let peakH = peakW * style.deckPhotoAspect
        let cardCenter = CGPoint(x: CGFloat(widthPx) / 2, y: CGFloat(heightPx) * 0.55)
        let matteRect = CGRect(x: cardCenter.x - peakW / 2, y: cardCenter.y - peakH / 2, width: peakW, height: peakH)

        // The photo card (back-stack + matte + image) scales about its center;
        // the caption + dots fade in once it is mostly open.
        context.saveGState()
        context.translateBy(x: cardCenter.x, y: cardCenter.y)
        context.scaleBy(x: scaleValue, y: scaleValue)
        context.translateBy(x: -cardCenter.x, y: -cardCenter.y)
        drawDeckStack(matteRect: matteRect, count: count, in: context)
        drawDeckHero(photos[index], matteRect: matteRect, in: context)
        context.restoreGState()

        let captionAlpha = CGFloat(min(max((scaleValue - 0.4) / 0.6, 0), 1))
        if captionAlpha > 0.001 {
            context.saveGState()
            context.setAlpha(captionAlpha)
            drawDeckCaption(card: card, below: matteRect, in: context)
            drawDeckDots(count: count, current: index, below: matteRect, in: context)
            context.restoreGState()
        }
    }

    /// Two dimmed cards peeking behind the hero to read as a deck (only with
    /// more than one photo). Offset toward the top-right in CG space.
    private func drawDeckStack(matteRect: CGRect, count: Int, in context: CGContext) {
        guard count > 1 else { return }
        let corner = style.deckCornerPx * scale
        for depth in [2, 1] {
            let offset = CGFloat(depth) * 12 * scale
            let rect = matteRect.offsetBy(dx: offset, dy: offset)
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.45))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.fillPath()
        }
    }

    /// Matte + aspect-filled hero photo, with a soft drop shadow for separation.
    private func drawDeckHero(_ photo: CGImage, matteRect: CGRect, in context: CGContext) {
        let corner = style.deckCornerPx * scale
        context.saveGState()
        context.setShadow(offset: .zero, blur: 24 * scale, color: style.deckShadowColor)
        context.setFillColor(style.deckMatteColor)
        context.addPath(CGPath(roundedRect: matteRect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.fillPath()
        context.restoreGState()

        let inset = style.deckMattePx * scale
        let imageRect = matteRect.insetBy(dx: inset, dy: inset)
        let imageCorner = max(corner - inset, 0)
        context.saveGState()
        context.addPath(CGPath(roundedRect: imageRect, cornerWidth: imageCorner, cornerHeight: imageCorner, transform: nil))
        context.clip()
        // Aspect-fill: cover the frame, crop the overflow.
        let iw = CGFloat(photo.width), ih = CGFloat(photo.height)
        let fill = max(imageRect.width / iw, imageRect.height / ih)
        let drawSize = CGSize(width: iw * fill, height: ih * fill)
        context.draw(photo, in: CGRect(
            x: imageRect.midX - drawSize.width / 2,
            y: imageRect.midY - drawSize.height / 2,
            width: drawSize.width, height: drawSize.height
        ))
        context.restoreGState()
    }

    /// Stop name under the photo, with the day label (and any walk detail)
    /// beneath it — centered, so the deck keeps the stop's identity.
    private func drawDeckCaption(card: StopCard, below matteRect: CGRect, in context: CGContext) {
        let gap = style.cardPaddingPx * scale
        let nameH = style.deckCaptionFontPx * scale
        let subH = style.subtitleFontPx * scale
        let nameBaseline = matteRect.minY - gap - nameH
        drawCenteredText(
            card.name, baselineY: nameBaseline,
            fontPx: style.deckCaptionFontPx, color: style.deckCaptionColor, in: context
        )
        let sub = [card.dayLabel, card.detail].compactMap { $0 }.joined(separator: " · ")
        drawCenteredText(
            sub, baselineY: nameBaseline - gap / 2 - subH,
            fontPx: style.subtitleFontPx, color: style.deckCaptionColor, in: context
        )
    }

    /// Progress dots: one per deck photo, the current one filled.
    private func drawDeckDots(count: Int, current: Int, below matteRect: CGRect, in context: CGContext) {
        let radius = style.deckDotRadiusPx * scale
        let spacing = radius * 3.2
        let nameH = style.deckCaptionFontPx * scale
        let subH = style.subtitleFontPx * scale
        let gap = style.cardPaddingPx * scale
        let dotsY = matteRect.minY - gap - nameH - gap / 2 - subH - gap - radius
        let totalW = spacing * CGFloat(count - 1)
        var dotX = CGFloat(widthPx) / 2 - totalW / 2
        for dot in 0..<count {
            context.setFillColor(dot == current ? style.deckDotOnColor : style.deckDotOffColor)
            context.fillEllipse(in: CGRect(x: dotX - radius, y: dotsY - radius, width: radius * 2, height: radius * 2))
            dotX += spacing
        }
    }

    /// smoothstep on an already-normalized fraction (clamped) — reused by the
    /// deck envelope so its grow/shrink eases like the camera legs.
    private func smoothstepFraction(_ fraction: Double) -> CGFloat {
        let clamped = min(max(fraction, 0), 1)
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
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
