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
/// **The closing card is full-bleed; the opening title is not** (Chiu
/// 2026-08-02). Both used to be a rounded white plate against one edge; both then
/// became full-frame scrims with a centred stack. That is still right for the
/// ending, which is a card *about* the trip.
///
/// It was wrong for the opening. A scrim across the whole frame makes the map
/// decorative — a texture behind the type — at the one moment its only job is to
/// say *where this happened*. The establishing shot already frames the whole
/// country; a viewer should recognise it from its own coastline, not be told by
/// text lying on top of it. So the title now sits in a **lower band**: the type
/// has its own ground to stand on and stays fully legible, while the upper frame
/// is left completely clear for the map to be read as a place.
extension RecapOverlayRenderer {
    /// Opening title: the trip's name **under** its own geography.
    ///
    /// Three things, in the order a viewer needs them: the branding (small — it
    /// signs the film, it is not the subject), the trip's name, and its dates.
    /// All inside the lower band, so the establishing shot above stays untouched.
    func drawTitleChrome(title: String, subtitle: String, into surface: RenderSurface) {
        let scale = surface.scale
        let bandHeight = CGFloat(surface.heightPx) * style.titleBandHeightFraction
        drawTitleBand(height: bandHeight, into: surface)

        // A wider margin than the rest of the chrome: this is the one line a
        // viewer reads cold, and type running edge to edge reads as a caption
        // rather than as a title.
        let sideMargin = style.cardMarginPx * scale * style.titleSideMarginScale
        let titleFontPx = fittedFontPx(
            title, preferred: style.titleFontPx,
            maxWidth: CGFloat(surface.widthPx) - sideMargin * 2, in: surface
        )
        let markSide = style.titleMarkSidePx * scale * style.titleBandMarkScale
        let brandPx = style.subtitleFontPx
        let titleH = titleFontPx * scale
        let metaH = style.subtitleFontPx * scale
        let gap = style.cardPaddingPx * scale
        let centerX = CGFloat(surface.widthPx) / 2

        // Walk down from the top of the stack, the same idiom the end card uses:
        // branding, then the trip's name, then its dates.
        let stackH = markSide + gap * 1.2 + titleH + gap * 0.8 + metaH
        var cursorY = (bandHeight * style.titleStackCenterFraction) + stackH / 2

        cursorY -= markSide
        let brandW = textWidth(RecapWordmark.text, fontPx: brandPx, in: surface)
        let lockupW = markSide + gap * 0.5 + brandW
        drawMark(
            centeredAt: CGPoint(x: centerX - lockupW / 2 + markSide / 2, y: cursorY + markSide / 2),
            side: markSide, in: surface
        )
        drawText(
            RecapWordmark.text,
            at: CGPoint(x: centerX - lockupW / 2 + markSide + gap * 0.5, y: cursorY + markSide * 0.32),
            fontPx: brandPx, color: style.chromeMetaColor, in: surface
        )

        cursorY -= gap * 1.2 + titleH
        drawCenteredText(
            title, centerX: centerX, baselineY: cursorY + titleH * 0.22,
            fontPx: titleFontPx, color: style.chromeTitleColor, in: surface
        )

        cursorY -= gap * 0.8 + metaH
        drawCenteredText(
            subtitle.uppercased(), centerX: centerX, baselineY: cursorY + metaH * 0.22,
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
        guard style.endCard == .full else { return drawMinimalEndChrome(into: surface) }
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

    /// The premium sign-off: a small mark and wordmark in the top-right corner,
    /// over an unobscured map.
    ///
    /// The reveal has just opened the frame onto the whole journey, and this
    /// treatment's whole argument is that *that* is the ending — the route you
    /// travelled, held for a beat — rather than a panel of numbers drawn over the
    /// top of it. So there is no scrim, no stats, and no call to action: nothing
    /// that would ask the map to recede at the exact moment it finally shows
    /// everything.
    private func drawMinimalEndChrome(into surface: RenderSurface) {
        let scale = surface.scale
        let markSide = style.minimalMarkSidePx * scale
        let margin = style.cardMarginPx * scale
        let wordmarkPx = style.subtitleFontPx
        let wordmarkW = textWidth(RecapWordmark.text, fontPx: wordmarkPx, in: surface)
        let gap = markSide * 0.35

        // Right-aligned as a unit: mark, then wordmark, hugging the top-right.
        let rightEdge = CGFloat(surface.widthPx) - margin
        let centreY = CGFloat(surface.heightPx) - margin - markSide / 2
        drawMark(
            centeredAt: CGPoint(x: rightEdge - wordmarkW - gap - markSide / 2, y: centreY),
            side: markSide, in: surface
        )
        drawText(
            RecapWordmark.text,
            at: CGPoint(x: rightEdge - wordmarkW, y: centreY - wordmarkPx * scale * 0.35),
            fontPx: wordmarkPx, color: style.chromeTitleColor, in: surface
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

    /// The band the opening title stands on.
    ///
    /// **Solid where the type is, fading only above it.** A gradient running the
    /// whole height puts the text in the middle of the ramp, at roughly half the
    /// opacity — which is where a title over dark terrain stops being readable.
    /// So the wash holds full strength up to `titleBandSolidFraction` and does all
    /// its fading in the remainder, leaving no visible edge against the map.
    private func drawTitleBand(height: CGFloat, into surface: RenderSurface) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let solid = style.chromeScrimColor.copy(alpha: style.titleBandOpacity),
              let clear = style.chromeScrimColor.copy(alpha: 0),
              let gradient = CGGradient(
                  colorsSpace: space, colors: [solid, solid, clear] as CFArray,
                  locations: [0, style.titleBandSolidFraction, 1]
              )
        else { return }
        surface.context.saveGState()
        surface.context.clip(to: CGRect(x: 0, y: 0, width: CGFloat(surface.widthPx), height: height))
        surface.context.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: height), options: []
        )
        surface.context.restoreGState()
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
