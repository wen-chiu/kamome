import CoreGraphics
import Foundation

/// Trip chrome for the overlay renderer (§4.5 step 4) — title panel and the
/// end panel with the "Get this route" QR, generated from `shareURL` (the data
/// layer carries the string, the renderer makes the code). Ported from the old
/// `RecapCardDrawing`; split out to keep each file readable.
extension RecapOverlayRenderer {
    func drawTitleChrome(title: String, subtitle: String, into surface: RenderSurface) {
        let scale = surface.scale
        let margin = style.cardMarginPx * scale
        let padding = style.cardPaddingPx * scale
        let titleHeight = style.titleFontPx * scale
        let subtitleHeight = style.subtitleFontPx * scale
        let panelHeight = padding * 2 + titleHeight + padding / 2 + subtitleHeight
        let rect = CGRect(
            x: margin, y: CGFloat(surface.heightPx) - margin - panelHeight,
            width: CGFloat(surface.widthPx) - margin * 2, height: panelHeight
        )
        fillPanel(rect, in: surface)
        let centerX = CGFloat(surface.widthPx) / 2
        drawCenteredText(
            title, centerX: centerX, baselineY: rect.maxY - padding - titleHeight * 0.8,
            fontPx: style.titleFontPx, color: style.cardTextColor, in: surface
        )
        drawCenteredText(
            subtitle, centerX: centerX, baselineY: rect.minY + padding,
            fontPx: style.subtitleFontPx, color: style.cardTextColor, in: surface
        )
    }

    func drawEndChrome(stats: [String], callToAction: String, shareURL: String, into surface: RenderSurface) {
        let scale = surface.scale
        let margin = style.cardMarginPx * scale
        let padding = style.cardPaddingPx * scale
        let statLineHeight = style.statFontPx * scale * 1.4
        let qrSide = style.qrSidePx * scale
        let ctaHeight = style.subtitleFontPx * scale
        let panelHeight = padding * 2 + CGFloat(stats.count) * statLineHeight
            + padding / 2 + qrSide + padding / 2 + ctaHeight
        let rect = CGRect(
            x: margin, y: (CGFloat(surface.heightPx) - panelHeight) / 2,
            width: CGFloat(surface.widthPx) - margin * 2, height: panelHeight
        )
        fillPanel(rect, in: surface)
        let centerX = CGFloat(surface.widthPx) / 2

        var baselineY = rect.maxY - padding - style.statFontPx * scale * 0.8
        for statLine in stats {
            drawCenteredText(
                statLine, centerX: centerX, baselineY: baselineY,
                fontPx: style.statFontPx, color: style.cardTextColor, in: surface
            )
            baselineY -= statLineHeight
        }
        if let qrCode = RecapQRCode.image(for: shareURL, sidePx: Int(style.qrSidePx)) {
            let qrRect = CGRect(
                x: rect.midX - qrSide / 2, y: rect.minY + padding + ctaHeight + padding / 2,
                width: qrSide, height: qrSide
            )
            surface.context.saveGState()
            surface.context.interpolationQuality = .none  // keep the QR modules crisp
            surface.context.draw(qrCode, in: qrRect)
            surface.context.restoreGState()
        }
        drawCenteredText(
            callToAction, centerX: centerX, baselineY: rect.minY + padding,
            fontPx: style.subtitleFontPx, color: style.cardTextColor, in: surface
        )
    }

    private func fillPanel(_ rect: CGRect, in surface: RenderSurface) {
        let corner = style.cardCornerPx * surface.scale
        surface.context.setFillColor(style.cardColor)
        surface.context.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        surface.context.fillPath()
    }
}
