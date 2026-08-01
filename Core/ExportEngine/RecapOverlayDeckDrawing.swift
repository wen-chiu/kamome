import CoreGraphics
import Foundation

/// The stop's photo presentation, split out of `RecapOverlayRenderer` the same
/// way the route and chrome drawing are — and because this is the beat the film
/// exists for: the map says *where*, this says *what you saw there*.
///
/// Ported from the validated web prototype (`Docs/prototype/recap_engine.html`,
/// `.cluster` / `.cards` / `.card` / `.hud`) rather than eyeballed from its
/// screenshots, so every measurement here traces to a CSS declaration quoted in
/// `RecapStyle`. Three layers, drawn back to front:
///
///   1. **map** — untouched. The pin stays on the stop and the trail stays
///      visible around the card; no scrim, no flat panel. Task-4 of the
///      2026-07-31 pass, and the reason the card is sized in *fractions* of the
///      frame rather than filling it.
///   2. **photo** — two secondary cards peeking out behind the hero, offset and
///      rotated, then the hero itself: portrait, strongly rounded, white
///      keyline, heavy drop shadow.
///   3. **typography** — the place's name and its accent strap under the photo.
///      Which day it is and how far the journey has come are *not* here: they are
///      facts about the film, not about one photograph, and live in the
///      persistent `hud` overlay (Chiu 2026-07-31).
///
/// What this is *not*: the fanned-stack carousel the prototype also shows. That
/// changes what a deck has to express (per-card transforms driven by a moving
/// front index, not one focused photo) and is scoped separately — handoff §"Photo
/// deck → fan/stack carousel".
extension RecapOverlayRenderer {
    /// The card opens from `deckPhotoMinWidthFraction` to
    /// `deckPhotoMaxWidthFraction` on the timeline's `reveal`, so the photo grows
    /// as the shot opens and still leaves the map and trail visible around its
    /// edges (Chiu 2026-07-25).
    ///
    /// Beat 2 keeps beat 1's geometry: **the pin does not move**. The stop's name
    /// still stands on it and the card opens above the pair, so the photos read as
    /// growing out of the place they were taken near rather than floating over the
    /// map on their own (Chiu 2026-07-26).
    func drawPhotoDeck(_ deck: RecapPhotoDeck, into surface: RenderSurface) {
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
        let identity = RecapStopIdentity(
            name: deck.name, subtitle: Self.strap(detail: deck.detail), photoCount: count, focusIndex: index
        )
        // The frame-edge clamp is given the *cluster's* width — hero plus the two
        // peeks sticking out either side — so a stop near the edge keeps its whole
        // composition on screen instead of losing one peek off the border. The
        // hero is then inset back out of it.
        let overhang = count > 1 ? cardW * style.deckPeekOffsetFraction : 0
        let layout = place(
            cardSize: CGSize(width: cardW + overhang * 2, height: cardW * style.deckPhotoAspect),
            // The settled height, so which side the cluster hangs on is fixed for
            // the whole scene rather than recomputed as the card grows.
            maxCardHeight: settledCardHeight(in: surface),
            identity: identity,
            anchor: surface.cgPoint(lat: deck.coordinate.lat, lon: deck.coordinate.lon), in: surface
        )
        let heroRect = layout.cardRect.insetBy(dx: overhang, dy: 0)

        context.saveGState()
        context.setAlpha(CGFloat(deck.opacity))
        drawPin(at: layout.pinPoint, radius: style.labelPinRadiusPx * surface.scale, in: surface)
        drawPeekCards(deck.photos, heroRect: heroRect, targetPx: Int(maxW), in: surface)
        drawCard(
            resolver.image(for: deck.photos[index], targetPx: Int(maxW)),
            in: heroRect, rotationDegrees: 0, cardScale: 1, in: surface
        )
        drawIdentity(identity, in: layout.labelRect, surface: surface)
        context.restoreGState()
    }

    // MARK: - Photo layer

    /// The two secondary cards behind the hero — `.peekL` / `.peekR`. **Static**:
    /// they take fixed photos (the stop's 2nd and 3rd), never the rotating focus,
    /// so they read as the rest of the roll sitting under the picture rather than
    /// as a second thing to watch. A stop with one photo gets none.
    private func drawPeekCards(
        _ photos: [PhotoRef], heroRect: CGRect, targetPx: Int, in surface: RenderSurface
    ) {
        guard photos.count > 1 else { return }
        let offset = heroRect.width * style.deckPeekOffsetFraction
        let peeks = [
            (ref: photos[1], sign: CGFloat(-1)),
            (ref: photos[photos.count > 2 ? 2 : photos.count - 1], sign: CGFloat(1))
        ]
        for peek in peeks {
            drawCard(
                resolver.image(for: peek.ref, targetPx: targetPx),
                in: heroRect.offsetBy(dx: peek.sign * offset, dy: 0),
                rotationDegrees: peek.sign * style.deckPeekRotationDegrees,
                cardScale: style.deckPeekScale, in: surface
            )
        }
    }

    /// One card: white keyline, strongly rounded, heavy drop shadow, the photo
    /// clipped to fill it. `rotationDegrees` / `cardScale` are the CSS transform
    /// on the peek cards, applied through the CTM so the corner radius and the
    /// keyline scale with the card exactly as `transform: scale()` does.
    private func drawCard(
        _ photo: CGImage?, in rect: CGRect, rotationDegrees: CGFloat, cardScale: CGFloat,
        in surface: RenderSurface
    ) {
        let context = surface.context
        let corner = style.deckCornerPx * surface.scale
        let local = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)

        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: rotationDegrees * .pi / 180)
        context.scaleBy(x: cardScale, y: cardScale)

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -style.deckShadowOffsetPx * surface.scale),
            blur: style.deckShadowBlurPx * surface.scale, color: style.deckShadowColor
        )
        context.setFillColor(style.deckMatteColor)
        context.addPath(CGPath(roundedRect: local, cornerWidth: corner, cornerHeight: corner, transform: nil))
        context.fillPath()
        context.restoreGState()

        guard let photo else { return }
        let inset = style.deckMattePx * surface.scale
        let imageRect = local.insetBy(dx: inset, dy: inset)
        let imageCorner = max(corner - inset, 0)
        context.addPath(CGPath(roundedRect: imageRect, cornerWidth: imageCorner, cornerHeight: imageCorner, transform: nil))
        context.clip()
        let iw = CGFloat(photo.width), ih = CGFloat(photo.height)
        let fill = max(imageRect.width / iw, imageRect.height / ih)
        let drawSize = CGSize(width: iw * fill, height: ih * fill)
        context.draw(photo, in: CGRect(
            x: imageRect.midX - drawSize.width / 2, y: imageRect.midY - drawSize.height / 2,
            width: drawSize.width, height: drawSize.height
        ))
    }
}
