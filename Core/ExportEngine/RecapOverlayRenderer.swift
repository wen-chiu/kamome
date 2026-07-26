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
        case let .routeReveal(coordinates):
            drawRouteReveal(coordinates, into: surface)
        case let .stopLabel(name, coordinate, detail, opacity):
            guard opacity > 0.001 else { return }
            surface.context.saveGState()
            surface.context.setAlpha(CGFloat(opacity))
            drawStopLabel(name: name, coordinate: coordinate, detail: detail, into: surface)
            surface.context.restoreGState()
        case let .photoDeck(deck):
            drawPhotoDeck(deck, into: surface)
        case let .titleChrome(title, subtitle):
            drawTitleChrome(title: title, subtitle: subtitle, into: surface)
        case let .endChrome(stats, callToAction, shareURL):
            drawEndChrome(stats: stats, callToAction: callToAction, shareURL: shareURL, into: surface)
        }
    }

    // MARK: - Route reveal (the glowing traveled trail)

    /// Stroked twice when the theme asks for it: a wide translucent glow under a
    /// crisp core, which is what makes the trail read as *lit* on a dark map
    /// rather than as a flat polyline. The path is built once and reused.
    private func drawRouteReveal(_ coordinates: [RecapCoordinate], into surface: RenderSurface) {
        guard coordinates.count >= 2 else { return }
        let context = surface.context
        let path = CGMutablePath()
        path.move(to: surface.cgPoint(lat: coordinates[0].lat, lon: coordinates[0].lon))
        for coordinate in coordinates.dropFirst() {
            path.addLine(to: surface.cgPoint(lat: coordinate.lat, lon: coordinate.lon))
        }
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if (style.routeGlowColor.alpha) > 0.001 {
            context.setStrokeColor(style.routeGlowColor)
            context.setLineWidth(style.routeWidthPx * style.routeGlowWidthMultiple * surface.scale)
            context.addPath(path)
            context.strokePath()
        }
        context.setStrokeColor(style.routeColor)
        context.setLineWidth(style.routeWidthPx * surface.scale)
        context.addPath(path)
        context.strokePath()
    }

    // MARK: - Stop label (§5 beat 1: pin on the map, name floating over the car)

    /// The pin **and** its name pill float together above the vehicle, clear of
    /// it by the vehicle's own half-length plus `labelVehicleClearancePx`, so
    /// neither ever prints over the car (Chiu 2026-07-25). The group is centered
    /// on the stop's projected position, so it still reads as marking that spot —
    /// the parked vehicle itself is what sits on the exact point.
    private func drawStopLabel(
        name: String, coordinate: RecapCoordinate, detail: String?, into surface: RenderSurface
    ) {
        let scale = surface.scale
        let radius = style.labelPinRadiusPx * scale
        let gap = style.labelPinGapPx * scale
        let pillH = pillHeight(detail: detail, in: surface)
        let anchor = surface.cgPoint(lat: coordinate.lat, lon: coordinate.lon)
        // No card in this beat, so the name band *is* the group: it must clear the
        // vehicle outright, and stay in frame for a stop near the edge.
        let layout = place(
            cardSize: CGSize(width: 0, height: 0),
            labelBandHeight: pillH + gap + radius * 3,
            labelBandWidth: pillWidth(name: name, detail: detail, in: surface),
            anchor: anchor, in: surface
        )
        let band = layout.labelRect
        drawPin(at: CGPoint(x: band.midX, y: band.minY + radius * 1.5), radius: radius, in: surface)
        drawNamePill(
            name: name, detail: detail, centerX: band.midX,
            bottomY: band.minY + radius * 3 + gap, in: surface
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
    /// edges (Chiu 2026-07-25). The stop's pin + name ride under the card, and
    /// the whole group is placed **beside the vehicle** by `RecapStopLayout` —
    /// with a static camera the vehicle is wherever it really is, so a
    /// frame-centred card would sit on top of it.
    private func drawPhotoDeck(_ deck: RecapPhotoDeck, into surface: RenderSurface) {
        guard deck.opacity > 0.001, !deck.photos.isEmpty else { return }
        let context = surface.context
        let scale = surface.scale
        let count = deck.photos.count
        let index = min(max(deck.focusIndex, 0), count - 1)

        let minW = CGFloat(surface.widthPx) * style.deckPhotoMinWidthFraction
        let maxW = CGFloat(surface.widthPx) * style.deckPhotoMaxWidthFraction
        let cardW = minW + (maxW - minW) * CGFloat(min(max(deck.reveal, 0), 1))
        let gap = style.deckLabelGapPx * scale
        let pinRadius = style.labelPinRadiusPx * scale
        let pillH = pillHeight(detail: deck.detail, in: surface)
        let dotsBand = style.deckDotRadiusPx * 2 * scale + style.cardPaddingPx * scale
        let layout = place(
            cardSize: CGSize(width: cardW, height: cardW * style.deckPhotoAspect),
            labelBandHeight: dotsBand + gap + pinRadius * 3 + gap + pillH,
            labelBandWidth: pillWidth(name: deck.name, detail: deck.detail, in: surface),
            anchor: surface.cgPoint(lat: deck.coordinate.lat, lon: deck.coordinate.lon),
            in: surface
        )
        let image = resolver.image(for: deck.photos[index], targetPx: Int(maxW))

        context.saveGState()
        context.setAlpha(CGFloat(deck.opacity))
        drawDeckStack(matteRect: layout.cardRect, count: count, in: surface)
        drawDeckHero(image, matteRect: layout.cardRect, in: surface)
        drawDeckDots(count: count, current: index, below: layout.cardRect, in: surface)

        // Inside the name band the pin sits nearest the card and the name beyond
        // it, whichever side of the card the band landed on.
        let band = layout.labelRect
        let pinY = layout.labelIsAboveCard
            ? band.minY + dotsBand + gap + pinRadius * 1.5
            : band.maxY - dotsBand - gap - pinRadius * 1.5
        drawPin(at: CGPoint(x: band.midX, y: pinY), radius: pinRadius, in: surface)
        drawNamePill(
            name: deck.name, detail: deck.detail, centerX: band.midX,
            bottomY: layout.labelIsAboveCard
                ? pinY + pinRadius * 1.5 + gap
                : pinY - pinRadius * 1.5 - gap - pillH,
            in: surface
        )
        context.restoreGState()
    }

    /// Places a stop's card and name band relative to the vehicle.
    func place(
        cardSize: CGSize, labelBandHeight: CGFloat, labelBandWidth: CGFloat,
        anchor: CGPoint, in surface: RenderSurface
    ) -> RecapStopLayout {
        RecapStopLayout(
            anchor: anchor,
            cardSize: cardSize,
            labelBandHeight: labelBandHeight,
            labelBandWidth: labelBandWidth,
            clearance: (style.subjectLengthPx / 2 + style.labelVehicleClearancePx) * surface.scale,
            marginPx: style.cardMarginPx * surface.scale,
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
