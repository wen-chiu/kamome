import CoreGraphics
import Foundation

/// The product name as it appears in the film. Not localized — a wordmark is a
/// brand mark, the same in every language.
enum RecapWordmark {
    static let text = "Kamome"
}

/// Trip chrome for the overlay renderer (§4.5 step 4) — title panel and the
/// end panel, which carries either the share QR generated from `shareURL` (the
/// data layer carries the string, the renderer makes the code) or the Kamome
/// wordmark while no share URL exists. Ported from the old `RecapCardDrawing`;
/// split out to keep each file readable.
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

    /// The closing panel: stats, then either the share QR or — for the Replay
    /// MVP — the Kamome wordmark (PD-4).
    ///
    /// The only payload the MVP could encode is `kamome://route/<id>`, which
    /// resolves to nothing: scanning it opens no page, installs no app, loads no
    /// trip. A code that invites a scan and then does nothing is worse for the
    /// film than no code at all, so the space goes to the wordmark until the
    /// share URL exists (spec P6/P7). The QR path below is untouched and comes
    /// back the moment `shareURL` is non-nil again.
    func drawEndChrome(stats: [String], callToAction: String, shareURL: String?, into surface: RenderSurface) {
        let scale = surface.scale
        let margin = style.cardMarginPx * scale
        let padding = style.cardPaddingPx * scale
        let statLineHeight = style.statFontPx * scale * 1.4
        let markHeight = shareURL == nil ? style.wordmarkFontPx * scale : style.qrSidePx * scale
        let ctaHeight = style.subtitleFontPx * scale
        let panelHeight = padding * 2 + CGFloat(stats.count) * statLineHeight
            + padding / 2 + markHeight + padding / 2 + ctaHeight
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
        let markBottomY = rect.minY + padding + ctaHeight + padding / 2
        if let shareURL, let qrCode = RecapQRCode.image(for: shareURL, sidePx: Int(style.qrSidePx)) {
            let qrRect = CGRect(
                x: rect.midX - markHeight / 2, y: markBottomY, width: markHeight, height: markHeight
            )
            surface.context.saveGState()
            surface.context.interpolationQuality = .none  // keep the QR modules crisp
            surface.context.draw(qrCode, in: qrRect)
            surface.context.restoreGState()
        } else {
            drawCenteredText(
                RecapWordmark.text, centerX: centerX, baselineY: markBottomY + markHeight * 0.18,
                fontPx: style.wordmarkFontPx, color: style.cardTextColor, in: surface
            )
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
