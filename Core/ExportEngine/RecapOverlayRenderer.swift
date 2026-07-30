import CoreGraphics
import CoreText
import Foundation

/// Resolves a `PhotoRef` to a bitmap at draw size — the render layer loads
/// images, the data layer only points at them. The app supplies a PhotoKit
/// resolver; tests supply a synthetic stub. Returning nil (asset gone, denied)
/// is fine — the deck still blooms its matte.
public protocol RecapPhotoResolving {
    func image(for ref: PhotoRef, targetPx: Int) -> CGImage?
}

/// Layer 3 (concrete): draws `OverlayContent` over the map. Renders exactly what
/// it is told and never touches the camera — the camera choreography (incl. the
/// deck dolly) is the timeline's. Ported from the old `RecapCardDrawing`, plus
/// the new two-beat stop label; the deck now takes its `emphasis`/`focusIndex`
/// from the timeline rather than recomputing a window.
public struct RecapOverlayRenderer: OverlayRenderer {
    let style: RecapStyle
    private let resolver: RecapPhotoResolving

    public init(style: RecapStyle = RecapStyle(), resolver: RecapPhotoResolving) {
        self.style = style
        self.resolver = resolver
    }

    public func render(_ content: OverlayContent, camera: CameraFrame, into surface: RenderSurface) {
        switch content {
        case let .routeReveal(legs):
            for leg in legs { drawRouteLeg(leg, into: surface) }
        case let .stopLabel(name, coordinate, detail, dayLabel, travelledM, opacity):
            guard opacity > 0.001 else { return }
            surface.context.saveGState()
            surface.context.setAlpha(CGFloat(opacity))
            drawStopLabel(
                name: name, coordinate: coordinate,
                detail: Self.caption(dayLabel: dayLabel, travelledM: travelledM, detail: detail),
                into: surface
            )
            surface.context.restoreGState()
        case let .photoDeck(deck):
            drawPhotoDeck(deck, into: surface)
        case let .titleChrome(title, subtitle):
            drawTitleChrome(title: title, subtitle: subtitle, into: surface)
        case let .endChrome(stats, callToAction, shareURL):
            drawEndChrome(stats: stats, callToAction: callToAction, shareURL: shareURL, into: surface)
        }
    }

    /// The caption under a stop's name: which day of the trip it is, and how far
    /// the journey has come by the time it arrives (Chiu 2026-07-30). Both are
    /// data the trip already carries — the day from its dates, the distance from
    /// the route's own leg lengths — so this is presentation, not new modelling.
    static func caption(dayLabel: String, travelledM: Double, detail: String?) -> String? {
        var parts: [String] = []
        if !dayLabel.isEmpty { parts.append(dayLabel) }
        if travelledM >= 100 { parts.append("\(Int((travelledM / 1000).rounded())) km") }
        if let detail, !detail.isEmpty { parts.append(detail) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Stop label (§5 beat 1: the pin lands on the stop, name above it)

    /// Beat 1: the pin lands **on the stop's own projected point** and its name
    /// stands on top of it (Chiu 2026-07-26). This beat cross-fades in exactly as
    /// the car parks, so the spot's identity is handed from vehicle to pin without
    /// ever moving across the map.
    private func drawStopLabel(
        name: String, coordinate: RecapCoordinate, detail: String?, into surface: RenderSurface
    ) {
        let layout = place(
            cardSize: .zero, name: name, detail: detail,
            anchor: surface.cgPoint(lat: coordinate.lat, lon: coordinate.lon), in: surface
        )
        drawPin(at: layout.pinPoint, radius: style.labelPinRadiusPx * surface.scale, in: surface)
        drawNamePill(
            name: name, detail: detail, centerX: layout.labelRect.midX,
            bottomY: layout.labelRect.minY, in: surface
        )
    }

    /// The pill's drawn width — the lead-in group's only horizontal extent.
    private func pillWidth(name: String, detail: String?, in surface: RenderSurface) -> CGFloat {
        let padding = style.labelPillPaddingPx * surface.scale
        let nameW = textWidth(name, fontPx: style.labelFontPx, in: surface)
        let detailW = detail.map { textWidth($0, fontPx: style.labelDetailFontPx, in: surface) } ?? 0
        return max(nameW, detailW) + padding * 2
    }

    /// A white ring under a colored dot, so the stop point reads on any terrain.
    private func drawPin(at center: CGPoint, radius: CGFloat, in surface: RenderSurface) {
        let context = surface.context
        context.setFillColor(style.labelPinRingColor)
        context.fillEllipse(in: CGRect(
            x: center.x - radius * 1.5, y: center.y - radius * 1.5, width: radius * 3, height: radius * 3
        ))
        context.setFillColor(style.labelPinColor)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// The name pill (plus optional detail line) sitting on `bottomY`, centered
    /// on `centerX`. Shared by the lead-in label and the deck's caption group so
    /// the stop's identity is drawn identically in both beats.
    @discardableResult
    private func drawNamePill(
        name: String, detail: String?, centerX: CGFloat, bottomY: CGFloat, in surface: RenderSurface
    ) -> CGRect {
        let context = surface.context
        let scale = surface.scale
        let padding = style.labelPillPaddingPx * scale
        let nameH = style.labelFontPx * scale
        let detailH = detail == nil ? 0 : style.labelDetailFontPx * scale
        let innerGap = detail == nil ? 0 : padding / 2
        let nameW = textWidth(name, fontPx: style.labelFontPx, in: surface)
        let detailW = detail.map { textWidth($0, fontPx: style.labelDetailFontPx, in: surface) } ?? 0
        let pillW = max(nameW, detailW) + padding * 2
        let pillH = padding * 2 + nameH + innerGap + detailH
        let pillRect = CGRect(x: centerX - pillW / 2, y: bottomY, width: pillW, height: pillH)

        context.setFillColor(style.labelPillColor)
        context.addPath(CGPath(
            roundedRect: pillRect, cornerWidth: pillH / 2.4, cornerHeight: pillH / 2.4, transform: nil
        ))
        context.fillPath()

        drawCenteredText(
            name, centerX: centerX, baselineY: pillRect.maxY - padding - nameH * 0.82,
            fontPx: style.labelFontPx, color: style.labelTextColor, in: surface
        )
        if let detail {
            drawCenteredText(
                detail, centerX: centerX, baselineY: pillRect.minY + padding,
                fontPx: style.labelDetailFontPx, color: style.labelDetailColor, in: surface
            )
        }
        return pillRect
    }

    // MARK: - Photo deck (zoom-in reveal, driven by the timeline's reveal/opacity)

    /// The card opens from `deckPhotoMinWidthFraction` to
    /// `deckPhotoMaxWidthFraction` on the timeline's `reveal`, so the photo grows
    /// as the shot opens and still leaves the map and trail visible around its
    /// edges (Chiu 2026-07-25).
    ///
    /// Beat 2 keeps beat 1's geometry: **the pin does not move**. The name pill
    /// still stands on it and the card opens above the pair, so the photos read as
    /// growing out of the place they were taken near rather than floating over the
    /// map on their own (Chiu 2026-07-26).
    private func drawPhotoDeck(_ deck: RecapPhotoDeck, into surface: RenderSurface) {
        guard deck.opacity > 0.001, !deck.photos.isEmpty else { return }
        let context = surface.context
        let count = deck.photos.count
        let index = min(max(deck.focusIndex, 0), count - 1)

        let minW = CGFloat(surface.widthPx) * style.deckPhotoMinWidthFraction
        let maxW = CGFloat(surface.widthPx) * style.deckPhotoMaxWidthFraction
        // Clamped to the overshoot ceiling, not to 1: the timeline's bloom
        // deliberately passes full size and settles back, and clamping here
        // would flatten that into a plain grow.
        let reveal = min(max(CGFloat(deck.reveal), 0), 1 + style.deckRevealOvershoot)
        let cardW = minW + (maxW - minW) * reveal
        let layout = place(
            cardSize: CGSize(width: cardW, height: cardW * style.deckPhotoAspect),
            name: deck.name,
            detail: Self.caption(dayLabel: deck.dayLabel, travelledM: deck.travelledM, detail: deck.detail),
            anchor: surface.cgPoint(lat: deck.coordinate.lat, lon: deck.coordinate.lon),
            in: surface
        )
        let image = resolver.image(for: deck.photos[index], targetPx: Int(maxW))

        context.saveGState()
        context.setAlpha(CGFloat(deck.opacity))
        drawDeckStack(matteRect: layout.cardRect, count: count, in: surface)
        drawDeckHero(image, matteRect: layout.cardRect, in: surface)
        drawDeckDots(count: count, current: index, below: layout.cardRect, in: surface)
        drawPin(at: layout.pinPoint, radius: style.labelPinRadiusPx * surface.scale, in: surface)
        drawNamePill(
            name: deck.name,
            detail: Self.caption(dayLabel: deck.dayLabel, travelledM: deck.travelledM, detail: deck.detail),
            centerX: layout.labelRect.midX, bottomY: layout.labelRect.minY, in: surface
        )
        context.restoreGState()
    }

    /// Places a stop's pin, name pill and card — all anchored on the stop itself.
    func place(
        cardSize: CGSize, name: String, detail: String?, anchor: CGPoint, in surface: RenderSurface
    ) -> RecapStopLayout {
        let scale = surface.scale
        return RecapStopLayout(
            anchor: anchor,
            cardSize: cardSize,
            pinHeight: style.labelPinRadiusPx * 3 * scale,
            labelBandHeight: pillHeight(detail: detail, in: surface),
            labelBandWidth: pillWidth(name: name, detail: detail, in: surface),
            gap: style.labelPinGapPx * scale,
            marginPx: style.cardMarginPx * scale,
            frameSize: CGSize(width: surface.widthPx, height: surface.heightPx)
        )
    }

    /// The pill's drawn height — needed to park it *below* an anchor.
    private func pillHeight(detail: String?, in surface: RenderSurface) -> CGFloat {
        let scale = surface.scale
        let padding = style.labelPillPaddingPx * scale
        let detailH = detail == nil ? 0 : style.labelDetailFontPx * scale
        let innerGap = detail == nil ? 0 : padding / 2
        return padding * 2 + style.labelFontPx * scale + innerGap + detailH
    }

    private func drawDeckStack(matteRect: CGRect, count: Int, in surface: RenderSurface) {
        guard count > 1 else { return }
        let context = surface.context
        let corner = style.deckCornerPx * surface.scale
        for depth in [2, 1] {
            let rect = matteRect.offsetBy(dx: CGFloat(depth) * 12 * surface.scale, dy: CGFloat(depth) * 12 * surface.scale)
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.45))
            context.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.fillPath()
        }
    }

    private func drawDeckHero(_ photo: CGImage?, matteRect: CGRect, in surface: RenderSurface) {
        let context = surface.context
        let corner = style.deckCornerPx * surface.scale
        context.saveGState()
        context.setShadow(offset: .zero, blur: 24 * surface.scale, color: style.deckShadowColor)
        context.setFillColor(style.deckMatteColor)
        context.addPath(CGPath(roundedRect: matteRect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.fillPath()
        context.restoreGState()

        guard let photo else { return }
        let inset = style.deckMattePx * surface.scale
        let imageRect = matteRect.insetBy(dx: inset, dy: inset)
        let imageCorner = max(corner - inset, 0)
        context.saveGState()
        context.addPath(CGPath(roundedRect: imageRect, cornerWidth: imageCorner, cornerHeight: imageCorner, transform: nil))
        context.clip()
        let iw = CGFloat(photo.width), ih = CGFloat(photo.height)
        let fill = max(imageRect.width / iw, imageRect.height / ih)
        let drawSize = CGSize(width: iw * fill, height: ih * fill)
        context.draw(photo, in: CGRect(
            x: imageRect.midX - drawSize.width / 2, y: imageRect.midY - drawSize.height / 2,
            width: drawSize.width, height: drawSize.height
        ))
        context.restoreGState()
    }

    private func drawDeckDots(count: Int, current: Int, below matteRect: CGRect, in surface: RenderSurface) {
        let context = surface.context
        let radius = style.deckDotRadiusPx * surface.scale
        let spacing = radius * 3.2
        let dotsY = matteRect.minY - style.cardPaddingPx * surface.scale - radius
        let totalW = spacing * CGFloat(count - 1)
        var dotX = CGFloat(surface.widthPx) / 2 - totalW / 2
        for dot in 0..<count {
            context.setFillColor(dot == current ? style.deckDotOnColor : style.deckDotOffColor)
            context.fillEllipse(in: CGRect(x: dotX - radius, y: dotsY - radius, width: radius * 2, height: radius * 2))
            dotX += spacing
        }
    }

    // MARK: - Text helpers

    func textWidth(_ text: String, fontPx: CGFloat, in surface: RenderSurface) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line(text, fontPx: fontPx, scale: surface.scale), nil, nil, nil))
    }

    func drawCenteredText(
        _ text: String, centerX: CGFloat, baselineY: CGFloat, fontPx: CGFloat, color: CGColor, in surface: RenderSurface
    ) {
        let width = textWidth(text, fontPx: fontPx, in: surface)
        drawText(text, at: CGPoint(x: centerX - width / 2, y: baselineY), fontPx: fontPx, color: color, in: surface)
    }

    func drawText(_ text: String, at origin: CGPoint, fontPx: CGFloat, color: CGColor, in surface: RenderSurface) {
        surface.context.saveGState()
        surface.context.textPosition = origin
        CTLineDraw(line(text, fontPx: fontPx, scale: surface.scale, color: color), surface.context)
        surface.context.restoreGState()
    }

    private func line(_ text: String, fontPx: CGFloat, scale: CGFloat, color: CGColor? = nil) -> CTLine {
        var attributes: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontPx * scale, nil)
        ]
        if let color { attributes[kCTForegroundColorAttributeName] = color }
        let attributed = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attributes as CFDictionary)
        return CTLineCreateWithAttributedString(attributed!)
    }
}
