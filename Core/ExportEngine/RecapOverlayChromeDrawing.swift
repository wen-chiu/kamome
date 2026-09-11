import CoreGraphics
import Foundation

/// The product name as it appears in the film, and the line under it. Neither is
/// localized — a wordmark is a brand mark, the same in every language, and so is
/// a tagline.
enum RecapWordmark {
    static let text = "Kamome"

    /// **The film's closing line** (Chiu 2026-09-05). It replaced `recap_end_cta`
    /// — *"Record your own journey"*, a localized call to action carried through
    /// the narrow waist as `RecapTrip.callToAction` — and the string, the field
    /// and the overlay's parameter went with it.
    ///
    /// 🔴 **Deliberately not localized, on the wordmark's own argument.** Chiu
    /// named the standing: this is brand copy, not a sentence about a trip, so it
    /// belongs beside `text` rather than in `Localizable.xcstrings`. The film's
    /// chrome already works this way — the boarding pass's `FROM` / `TO` /
    /// `DISTANCE` / `DATE` are English literals by decision, and the HUD's `km`
    /// is un-localized so a frame renders identically on any device.
    static let tagline = "Turn your journey into memory."
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

    /// Closing card: what the journey came to, floating on the map it just drew.
    ///
    /// 🔴 **Neither a scrim nor a panel** (Chiu 2026-09-05, ADR 2026-09-05 (d)).
    /// The frame is dimmed a little so unplated type reads, and everything else
    /// is drawn straight onto the map — trail, coastline and stop pins all still
    /// visible. `RecapEndCardStyle` carries the three grounds that were tried and
    /// why this is the one. The framing is untouched.
    ///
    /// Top to bottom, per Chiu's layout: the mark, the **trip's name**, one row of
    /// three figures, then the wordmark with its line beneath.
    ///
    /// Carries the share QR in the mark's place when there is one — for the Replay
    /// MVP there is not (PD-4): `kamome://route/<id>` opens no page, installs no
    /// app, loads no trip, and a code inviting a scan nothing can honour is worse
    /// for the film than no code. The QR path returns the moment `shareURL` is
    /// non-nil.
    func drawEndChrome(
        title: String, figures: [RecapEndCardFigure], shareURL: String?, into surface: RenderSurface
    ) {
        guard style.endCard == .full else { return drawMinimalEndChrome(into: surface) }
        let scale = surface.scale
        let tokens = style.endCardStyle

        surface.context.setFillColor(tokens.dimColor)
        surface.context.fill(CGRect(x: 0, y: 0, width: surface.widthPx, height: surface.heightPx))

        // One halo for the whole stack — see `RecapEndCardStyle.typeShadowColor`
        // for why the type carries its own separation instead of the dim carrying
        // it. Everything below draws with `drawCenteredText`, never
        // `drawShadowedText`, which would replace this with the stop label's.
        surface.context.saveGState()
        defer { surface.context.restoreGState() }
        surface.context.setShadow(
            offset: .zero, blur: tokens.typeShadowBlurPx * scale, color: tokens.typeShadowColor
        )

        let markSide = shareURL == nil ? style.titleMarkSidePx * scale : style.qrSidePx * scale
        let sideMargin = style.cardMarginPx * scale * style.titleSideMarginScale
        let titleFontPx = fittedFontPx(
            title, preferred: style.titleFontPx,
            maxWidth: CGFloat(surface.widthPx) - sideMargin * 2, in: surface
        )
        let titleH = titleFontPx * scale
        let figuresH = (tokens.figureValueFontPx + tokens.figureLabelGapPx + tokens.figureLabelFontPx) * scale
        let wordmarkH = style.wordmarkFontPx * scale
        let taglineH = tokens.taglineFontPx * scale
        let gap = style.cardPaddingPx * scale

        let stackH = markSide + gap * 1.2 + titleH + gap * 2 + figuresH
            + gap * 2 + wordmarkH + gap * 0.5 + taglineH
        var cursorY = (CGFloat(surface.heightPx) + stackH) / 2
        let centerX = CGFloat(surface.widthPx) / 2

        cursorY -= markSide
        drawEndMark(shareURL: shareURL, centerX: centerX, bottomY: cursorY, side: markSide, in: surface)

        cursorY -= gap * 1.2 + titleH
        drawCenteredText(
            title, centerX: centerX, baselineY: cursorY + titleH * 0.22,
            fontPx: titleFontPx, color: style.chromeTitleColor, in: surface
        )

        cursorY -= gap * 2 + figuresH
        drawFigureRow(figures, topY: cursorY + figuresH, in: surface)

        cursorY -= gap * 2 + wordmarkH
        drawCenteredText(
            RecapWordmark.text, centerX: centerX, baselineY: cursorY + wordmarkH * 0.2,
            fontPx: style.wordmarkFontPx, color: style.chromeTitleColor, in: surface
        )

        // **Directly under the wordmark and smaller** (Chiu 2026-09-05): it reads
        // as that mark's line rather than as another row of the summary. Set as
        // written, not uppercased — it is a sentence with a full stop.
        cursorY -= gap * 0.5 + taglineH
        drawCenteredText(
            RecapWordmark.tagline, centerX: centerX, baselineY: cursorY + taglineH * 0.2,
            fontPx: tokens.taglineFontPx, color: style.chromeAccentColor, in: surface
        )
    }

    /// The brand mark, or the share QR when the film has a payload for one.
    private func drawEndMark(
        shareURL: String?, centerX: CGFloat, bottomY: CGFloat, side: CGFloat, in surface: RenderSurface
    ) {
        guard let shareURL, let qrCode = RecapQRCode.image(for: shareURL, sidePx: Int(style.qrSidePx)) else {
            return drawMark(centeredAt: CGPoint(x: centerX, y: bottomY + side / 2), side: side, in: surface)
        }
        surface.context.saveGState()
        surface.context.interpolationQuality = .none  // keep the QR modules crisp
        surface.context.draw(qrCode, in: CGRect(x: centerX - side / 2, y: bottomY, width: side, height: side))
        surface.context.restoreGState()
    }

    /// **`1,358 KM · 13 DAYS · 9 STOPS`, as three columns rather than a sentence**
    /// (Chiu 2026-09-05): each is a large number with its small tracked label
    /// under it, and the columns are spaced evenly across `figureRowWidthFraction`
    /// of the frame.
    ///
    /// `topY` is the top of the row — the value's own height — so the caller
    /// places the block and this fills it.
    ///
    /// Empty is a real state and draws nothing: a trip whose figures could not be
    /// composed closes on its name and its mark rather than on three blanks.
    private func drawFigureRow(_ figures: [RecapEndCardFigure], topY: CGFloat, in surface: RenderSurface) {
        guard !figures.isEmpty else { return }
        let scale = surface.scale
        let tokens = style.endCardStyle
        let valueH = tokens.figureValueFontPx * scale
        let labelH = tokens.figureLabelFontPx * scale
        let rowWidth = CGFloat(surface.widthPx) * tokens.figureRowWidthFraction
        let column = rowWidth / CGFloat(figures.count)
        let firstCentre = (CGFloat(surface.widthPx) - rowWidth) / 2 + column / 2

        for (index, figure) in figures.enumerated() {
            let centreX = firstCentre + column * CGFloat(index)
            drawCenteredText(
                figure.value,
                centerX: centreX, baselineY: topY - valueH + valueH * 0.22,
                fontPx: fittedFontPx(
                    figure.value, preferred: tokens.figureValueFontPx,
                    maxWidth: column * 0.9, in: surface
                ),
                color: style.chromeTitleColor, in: surface
            )
            drawCenteredText(
                figure.label,
                centerX: centreX,
                baselineY: topY - valueH - tokens.figureLabelGapPx * scale - labelH * 0.78,
                fontPx: tokens.figureLabelFontPx, color: style.chromeMetaColor,
                tracking: tokens.figureLabelFontPx * tokens.figureLabelTrackingEm * scale, in: surface
            )
        }
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
