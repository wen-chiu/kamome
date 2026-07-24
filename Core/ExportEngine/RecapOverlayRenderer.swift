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
        case let .stopLabel(name, coordinate, detail):
            drawStopLabel(name: name, coordinate: coordinate, detail: detail, into: surface)
        case let .photoDeck(deck):
            drawPhotoDeck(deck, into: surface)
        case let .titleChrome(title, subtitle):
            drawTitleChrome(title: title, subtitle: subtitle, into: surface)
        case let .endChrome(stats, callToAction, shareURL):
            drawEndChrome(stats: stats, callToAction: callToAction, shareURL: shareURL, into: surface)
        }
    }

    // MARK: - Route reveal (the glowing traveled trail)

    private func drawRouteReveal(_ coordinates: [RecapCoordinate], into surface: RenderSurface) {
        guard coordinates.count >= 2 else { return }
        let context = surface.context
        context.setStrokeColor(style.routeColor)
        context.setLineWidth(style.routeWidthPx * surface.scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: surface.cgPoint(lat: coordinates[0].lat, lon: coordinates[0].lon))
        for coordinate in coordinates.dropFirst() {
            context.addLine(to: surface.cgPoint(lat: coordinate.lat, lon: coordinate.lon))
        }
        context.strokePath()
    }

    // MARK: - Stop label (§5 two-beat lead: pin + name pill, anchored on the map)

    private func drawStopLabel(
        name: String, coordinate: RecapCoordinate, detail: String?, into surface: RenderSurface
    ) {
        let context = surface.context
        let scale = surface.scale
        let center = surface.cgPoint(lat: coordinate.lat, lon: coordinate.lon)
        let radius = style.labelPinRadiusPx * scale

        // Pin: a white ring under a colored dot, so it reads on any terrain.
        context.setFillColor(style.labelPinRingColor)
        context.fillEllipse(in: CGRect(
            x: center.x - radius * 1.5, y: center.y - radius * 1.5, width: radius * 3, height: radius * 3
        ))
        context.setFillColor(style.labelPinColor)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

        // Name pill floating above the pin (higher y in the CG bottom-left frame).
        let padding = style.labelPillPaddingPx * scale
        let nameH = style.labelFontPx * scale
        let detailH = detail == nil ? 0 : style.labelDetailFontPx * scale
        let innerGap = detail == nil ? 0 : padding / 2
        let nameW = textWidth(name, fontPx: style.labelFontPx, in: surface)
        let detailW = detail.map { textWidth($0, fontPx: style.labelDetailFontPx, in: surface) } ?? 0
        let pillW = max(nameW, detailW) + padding * 2
        let pillH = padding * 2 + nameH + innerGap + detailH
        let pillBottom = center.y + radius * 1.5 + style.labelPillGapPx * scale
        let pillRect = CGRect(x: center.x - pillW / 2, y: pillBottom, width: pillW, height: pillH)

        context.setFillColor(style.labelPillColor)
        context.addPath(CGPath(
            roundedRect: pillRect, cornerWidth: pillH / 2.4, cornerHeight: pillH / 2.4, transform: nil
        ))
        context.fillPath()

        drawCenteredText(
            name, centerX: center.x, baselineY: pillRect.maxY - padding - nameH * 0.82,
            fontPx: style.labelFontPx, color: style.labelTextColor, in: surface
        )
        if let detail {
            drawCenteredText(
                detail, centerX: center.x, baselineY: pillRect.minY + padding,
                fontPx: style.labelDetailFontPx, color: style.labelDetailColor, in: surface
            )
        }
    }

    // MARK: - Photo deck (bloom driven by the timeline's emphasis + focusIndex)

    private func drawPhotoDeck(_ deck: RecapPhotoDeck, into surface: RenderSurface) {
        guard deck.emphasis > 0.001, !deck.photos.isEmpty else { return }
        let context = surface.context
        let count = deck.photos.count
        let index = min(max(deck.focusIndex, 0), count - 1)

        let peakW = CGFloat(surface.widthPx) * style.deckPhotoWidthFraction
        let peakH = peakW * style.deckPhotoAspect
        let cardCenter = CGPoint(x: CGFloat(surface.widthPx) / 2, y: CGFloat(surface.heightPx) * 0.55)
        let matteRect = CGRect(x: cardCenter.x - peakW / 2, y: cardCenter.y - peakH / 2, width: peakW, height: peakH)
        let image = resolver.image(for: deck.photos[index], targetPx: Int(peakW))

        context.saveGState()
        context.translateBy(x: cardCenter.x, y: cardCenter.y)
        context.scaleBy(x: CGFloat(deck.emphasis), y: CGFloat(deck.emphasis))
        context.translateBy(x: -cardCenter.x, y: -cardCenter.y)
        drawDeckStack(matteRect: matteRect, count: count, in: surface)
        drawDeckHero(image, matteRect: matteRect, in: surface)
        context.restoreGState()

        let dotsAlpha = CGFloat(min(max((deck.emphasis - 0.4) / 0.6, 0), 1))
        if dotsAlpha > 0.001 {
            context.saveGState()
            context.setAlpha(dotsAlpha)
            drawDeckDots(count: count, current: index, below: matteRect, in: surface)
            context.restoreGState()
        }
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
