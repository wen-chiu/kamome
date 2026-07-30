import CoreGraphics
import Foundation

/// The product name as it appears in the film. Not localized — a wordmark is a
/// brand mark, the same in every language.
enum RecapWordmark {
    static let text = "Kamome"
}

/// Trip chrome for the overlay renderer (§4.5 step 4): the opening title and the
/// closing card.
///
/// **Full-bleed, not a panel** (Chiu 2026-07-30, matching the prototype). Both
/// cards used to be a rounded white plate parked against one edge, with the map
/// as the subject. They are now cinematic title screens: a dark scrim across the
/// whole frame, the map receding behind it, and a centred stack — mark, title,
/// then a metadata line. The map is background, not content, for these few
/// seconds.
extension RecapOverlayRenderer {
    /// Opening title: the trip's name over its own geography.
    func drawTitleChrome(title: String, subtitle: String, into surface: RenderSurface) {
        let scale = surface.scale
        drawScrim(into: surface)

        // The stack is centred as a group, so a long title and a short one both
        // sit balanced rather than one riding high.
        // A trip title is user data of any length, so the type shrinks to fit
        // rather than running off both edges — which is exactly what
        // "Iceland — Golden Circle" did at the full size.
        let titleFontPx = fittedFontPx(
            title, preferred: style.titleFontPx,
            maxWidth: CGFloat(surface.widthPx) - style.cardMarginPx * 2 * scale, in: surface
        )
        let markSide = style.titleMarkSidePx * scale
        let titleH = titleFontPx * scale
        let metaH = style.subtitleFontPx * scale
        let gap = style.cardPaddingPx * scale
        let stackH = markSide + gap * 1.5 + titleH + gap + metaH
        var cursorY = (CGFloat(surface.heightPx) + stackH) / 2
        let centerX = CGFloat(surface.widthPx) / 2

        cursorY -= markSide
        drawMark(centeredAt: CGPoint(x: centerX, y: cursorY + markSide / 2), side: markSide, in: surface)

        cursorY -= gap * 1.5 + titleH
        drawCenteredText(
            title, centerX: centerX, baselineY: cursorY + titleH * 0.2,
            fontPx: titleFontPx, color: style.chromeTitleColor, in: surface
        )

        cursorY -= gap + metaH
        drawCenteredText(
            subtitle.uppercased(), centerX: centerX, baselineY: cursorY + metaH * 0.2,
            fontPx: style.subtitleFontPx, color: style.chromeMetaColor, in: surface
        )
    }

    /// Closing card: what the journey came to, in the same visual language as the
    /// opening so the film is bracketed rather than merely ended.
    ///
    /// Carries either the share QR or — for the Replay MVP — the Kamome wordmark
    /// (PD-4). The only payload the MVP could encode is `kamome://route/<id>`,
    /// which resolves to nothing: scanning it opens no page, installs no app,
    /// loads no trip. A code that invites a scan and then does nothing is worse
    /// for the film than no code, so the space goes to the wordmark until the
    /// share URL exists (spec P6/P7). The QR path below is untouched and returns
    /// the moment `shareURL` is non-nil.
    func drawEndChrome(stats: [String], callToAction: String, shareURL: String?, into surface: RenderSurface) {
        let scale = surface.scale
        drawScrim(into: surface)

        let markSide = shareURL == nil ? style.titleMarkSidePx * scale : style.qrSidePx * scale
        let wordmarkH = style.wordmarkFontPx * scale
        let statH = style.statFontPx * scale * 1.4
        let ctaH = style.subtitleFontPx * scale
        let gap = style.cardPaddingPx * scale
        let stackH = markSide + gap + wordmarkH + gap * 1.5
            + CGFloat(stats.count) * statH + gap + ctaH
        var cursorY = (CGFloat(surface.heightPx) + stackH) / 2
        let centerX = CGFloat(surface.widthPx) / 2

        cursorY -= markSide
        if let shareURL, let qrCode = RecapQRCode.image(for: shareURL, sidePx: Int(style.qrSidePx)) {
            surface.context.saveGState()
            surface.context.interpolationQuality = .none  // keep the QR modules crisp
            surface.context.draw(qrCode, in: CGRect(
                x: centerX - markSide / 2, y: cursorY, width: markSide, height: markSide
            ))
            surface.context.restoreGState()
        } else {
            drawMark(centeredAt: CGPoint(x: centerX, y: cursorY + markSide / 2), side: markSide, in: surface)
        }

        cursorY -= gap + wordmarkH
        drawCenteredText(
            RecapWordmark.text, centerX: centerX, baselineY: cursorY + wordmarkH * 0.2,
            fontPx: style.wordmarkFontPx, color: style.chromeTitleColor, in: surface
        )

        cursorY -= gap * 1.5
        for statLine in stats {
            cursorY -= statH
            drawCenteredText(
                statLine, centerX: centerX, baselineY: cursorY + statH * 0.25,
                fontPx: style.statFontPx, color: style.chromeMetaColor, in: surface
            )
        }

        cursorY -= gap + ctaH
        drawCenteredText(
            callToAction.uppercased(), centerX: centerX, baselineY: cursorY + ctaH * 0.2,
            fontPx: style.subtitleFontPx, color: style.chromeAccentColor, in: surface
        )
    }

    /// The largest size at or below `preferred` that fits `maxWidth`. Text in a
    /// film cannot be truncated or wrapped away — it is on screen for seconds and
    /// then gone — so it scales instead.
    func fittedFontPx(
        _ text: String, preferred: CGFloat, maxWidth: CGFloat, in surface: RenderSurface
    ) -> CGFloat {
        guard !text.isEmpty else { return preferred }
        let measured = textWidth(text, fontPx: preferred, in: surface)
        guard measured > maxWidth, measured > 0 else { return preferred }
        return preferred * (maxWidth / measured)
    }

    /// The full-frame dark wash that pushes the map back. Strongest at the centre
    /// where the text sits, so the map still reads at the edges instead of the
    /// card looking like a flat black slide.
    private func drawScrim(into surface: RenderSurface) {
        let context = surface.context
        let rect = CGRect(x: 0, y: 0, width: surface.widthPx, height: surface.heightPx)
        context.setFillColor(style.chromeScrimColor)
        context.fill(rect)

        guard style.chromeScrimCenterBoost > 0.001,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let inner = style.chromeScrimColor.copy(alpha: style.chromeScrimCenterBoost),
              let outer = style.chromeScrimColor.copy(alpha: 0),
              let gradient = CGGradient(colorsSpace: space, colors: [inner, outer] as CFArray, locations: [0, 1])
        else { return }
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: rect.width / rect.height, y: 1)
        context.drawRadialGradient(
            gradient, startCenter: .zero, startRadius: 0,
            endCenter: .zero, endRadius: rect.height * 0.55, options: []
        )
        context.restoreGState()
    }

    /// The brand mark — the seagull Kamome is named for, drawn from the same
    /// vector the fallback vehicle marker uses rather than a bespoke asset.
    private func drawMark(centeredAt center: CGPoint, side: CGFloat, in surface: RenderSurface) {
        VehicleMarker.seagull.draw(
            in: surface.context, at: center, lengthPx: side, rotationDegrees: 0,
            colors: VehicleMarker.Palette(
                fill: style.chromeAccentColor,
                accent: style.chromeAccentColor,
                outline: style.chromeAccentColor
            )
        )
    }
}
