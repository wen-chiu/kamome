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

/// The type under a stop, as content rather than as drawing instructions: the
/// place's own name, the uppercase strap beneath it, and how many photos the
/// stop has to page through (0 = no progress dots).
///
/// Both beats of the stop scene build one of these, so beat 1's floating label
/// and beat 2's caption under the card are literally the same drawing — which is
/// what lets them cross-fade in place instead of jumping.
struct RecapStopIdentity {
    let name: String
    let subtitle: String?
    var photoCount: Int = 0
    var focusIndex: Int = 0
}

/// Layer 3 (concrete): draws `OverlayContent` over the map. Renders exactly what
/// it is told and never touches the camera — the camera choreography (incl. the
/// deck dolly) is the timeline's. Ported from the old `RecapCardDrawing`, plus
/// the new two-beat stop label; the deck now takes its `emphasis`/`focusIndex`
/// from the timeline rather than recomputing a window.
///
/// The stop presentation is three layered elements (Chiu 2026-07-31, ported from
/// `Docs/prototype/recap_engine.html`): **photo** (the hero card and the two
/// secondary cards peeking behind it), **map** (never covered — the pin stays on
/// the stop and the trail stays visible around the card), and **typography**
/// (the metadata pill over the photo, the place's name and strap under it).
public struct RecapOverlayRenderer: OverlayRenderer {
    let style: RecapStyle
    let resolver: RecapPhotoResolving

    public init(style: RecapStyle = RecapStyle(), resolver: RecapPhotoResolving) {
        self.style = style
        self.resolver = resolver
    }

    public func render(_ content: OverlayContent, camera: CameraFrame, into surface: RenderSurface) {
        switch content {
        case let .routeReveal(legs):
            for leg in legs { drawRouteLeg(leg, into: surface) }
        case let .stopLabel(name, coordinate, detail, opacity):
            guard opacity > 0.001 else { return }
            surface.context.saveGState()
            surface.context.setAlpha(CGFloat(opacity))
            drawStopLabel(
                identity: RecapStopIdentity(name: name, subtitle: Self.strap(detail: detail)),
                coordinate: coordinate, into: surface
            )
            surface.context.restoreGState()
        case let .photoDeck(deck):
            drawPhotoDeck(deck, into: surface)
        case let .journeyCard(card):
            drawJourneyCard(card, into: surface)
        case let .flightEnds(origin, destination, opacity):
            drawFlightEnds(origin: origin, destination: destination, opacity: opacity, into: surface)
        case let .hud(dayLabel, place, travelledM):
            drawHUD(dayLabel: dayLabel, place: place, travelledM: travelledM, into: surface)
        case let .titleChrome(title, subtitle):
            drawTitleChrome(title: title, subtitle: subtitle, into: surface)
        case let .endChrome(stats, callToAction, shareURL):
            drawEndChrome(stats: stats, callToAction: callToAction, shareURL: shareURL, into: surface)
        }
    }

    /// The strap under a stop's name: whatever second identity the stop carries
    /// (`detail` — the Latin/secondary name in the prototype, a walk's duration
    /// for a walk-visit). Uppercased and letter-spaced at draw time; absent when
    /// the stop has no second line, rather than padded with something to say.
    ///
    /// The day and the distance deliberately do **not** live here: they belong to
    /// the persistent HUD, which carries them on the road as well as at the stop
    /// (Chiu 2026-07-31). Repeating them under the photo would say the same thing
    /// twice in one frame and then take one copy away.
    static func strap(detail: String?) -> String? {
        guard let detail, !detail.isEmpty else { return nil }
        return detail.uppercased()
    }

    /// How far the journey has come, split into number and unit so the unit can
    /// recede (`.hud .km small`). Under 100 m is the opening of the film, where a
    /// "0 km" readout says nothing.
    static func distance(travelledM: Double) -> (value: String, unit: String)? {
        guard travelledM >= 100 else { return nil }
        return (grouped(Int((travelledM / 1000).rounded())), "km")
    }

    /// Thousands separators, done by hand rather than through `NumberFormatter`:
    /// a film's frames must be byte-identical run to run, and a formatter's
    /// output follows the device locale.
    static func grouped(_ value: Int) -> String {
        let digits = Array(String(value))
        return digits.enumerated().reduce(into: "") { text, item in
            let remaining = digits.count - item.offset
            if item.offset > 0, remaining % 3 == 0 { text.append(",") }
            text.append(item.element)
        }
    }

    // MARK: - Stop label (§5 beat 1: the pin lands on the stop, name above it)

    /// Beat 1: the pin lands **on the stop's own projected point** and its name
    /// stands on top of it (Chiu 2026-07-26). This beat cross-fades in exactly as
    /// the car parks, so the spot's identity is handed from vehicle to pin without
    /// ever moving across the map.
    private func drawStopLabel(
        identity: RecapStopIdentity, coordinate: RecapCoordinate, into surface: RenderSurface
    ) {
        // Beat 1 is placed against the card that is *about* to open, not against
        // the nothing it currently has. Otherwise the name picks a side on its
        // own and the card arriving flips the whole cluster underneath it.
        let layout = place(
            cardSize: .zero, maxCardHeight: settledCardHeight(in: surface), identity: identity,
            anchor: surface.cgPoint(lat: coordinate.lat, lon: coordinate.lon), in: surface
        )
        drawPin(at: layout.pinPoint, radius: style.labelPinRadiusPx * surface.scale, in: surface)
        drawIdentity(identity, in: layout.labelRect, surface: surface)
    }

    /// A white ring under a colored dot, so the stop point reads on any terrain.
    func drawPin(at center: CGPoint, radius: CGFloat, in surface: RenderSurface) {
        let context = surface.context
        context.setFillColor(style.labelPinRingColor)
        context.fillEllipse(in: CGRect(
            x: center.x - radius * 1.5, y: center.y - radius * 1.5, width: radius * 3, height: radius * 3
        ))
        context.setFillColor(style.labelPinColor)
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// The photo card's height once fully revealed. One definition, shared by
    /// both stop beats, so they can never disagree about which side to hang on.
    func settledCardHeight(in surface: RenderSurface) -> CGFloat {
        CGFloat(surface.widthPx) * style.deckPhotoMaxWidthFraction * style.deckPhotoAspect
    }

    /// Places a stop's pin, name group and card — all anchored on the stop itself.
    func place(
        cardSize: CGSize, maxCardHeight: CGFloat, identity: RecapStopIdentity,
        anchor: CGPoint, in surface: RenderSurface
    ) -> RecapStopLayout {
        let scale = surface.scale
        let metrics = identityMetrics(identity, in: surface)
        return RecapStopLayout(
            anchor: anchor,
            cardSize: cardSize,
            maxCardHeight: maxCardHeight,
            pinHeight: style.labelPinRadiusPx * 3 * scale,
            labelBandHeight: metrics.height,
            labelBandWidth: metrics.width,
            gap: style.labelPinGapPx * scale,
            marginPx: style.cardMarginPx * scale,
            frameSize: CGSize(width: surface.widthPx, height: surface.heightPx)
        )
    }

    // MARK: - Stop identity: name, strap, progress dots (the prototype's .clabel)

    /// The measured type block: sizes shrink to fit the frame, because a place
    /// name is user data of any length and film type can be neither wrapped nor
    /// truncated — it is on screen for seconds and then gone.
    struct IdentityMetrics {
        let nameFontPx: CGFloat
        let strapFontPx: CGFloat
        let strapTracking: CGFloat
        let dotsHeight: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    func identityMetrics(_ identity: RecapStopIdentity, in surface: RenderSurface) -> IdentityMetrics {
        let scale = surface.scale
        let maxWidth = CGFloat(surface.widthPx) - style.cardMarginPx * 2 * scale
        let nameFontPx = fittedFontPx(identity.name, preferred: style.labelFontPx, maxWidth: maxWidth, in: surface)
        var strapFontPx = style.labelDetailFontPx
        var strapTracking = strapFontPx * style.labelDetailTrackingEm * scale
        var strapWidth: CGFloat = 0
        if let subtitle = identity.subtitle {
            strapWidth = textWidth(subtitle, fontPx: strapFontPx, tracking: strapTracking, in: surface)
            if strapWidth > maxWidth, strapWidth > 0 {
                strapFontPx *= maxWidth / strapWidth
                strapTracking = strapFontPx * style.labelDetailTrackingEm * scale
                strapWidth = maxWidth
            }
        }
        let dotsHeight = identity.photoCount > 1
            ? (style.deckDotGapPx + style.deckDotRadiusPx * 2 * style.deckDotActiveScale) * scale
            : 0
        let strapHeight = identity.subtitle == nil ? 0 : (style.labelDetailGapPx * scale + strapFontPx * scale)
        return IdentityMetrics(
            nameFontPx: nameFontPx, strapFontPx: strapFontPx, strapTracking: strapTracking,
            dotsHeight: dotsHeight,
            width: max(textWidth(identity.name, fontPx: nameFontPx, in: surface), strapWidth),
            height: nameFontPx * scale + strapHeight + dotsHeight
        )
    }

    /// Draws the name, its uppercase accent strap and the progress dots, reading
    /// downward from the top of `rect` — the same order as the prototype's
    /// `.clabel` + `.dots`, and the same drawing in both beats of the stop.
    func drawIdentity(_ identity: RecapStopIdentity, in rect: CGRect, surface: RenderSurface) {
        let scale = surface.scale
        let metrics = identityMetrics(identity, in: surface)
        let centerX = rect.midX
        var cursorY = rect.maxY

        cursorY -= metrics.nameFontPx * scale
        drawShadowedText(
            identity.name, anchor: CGPoint(x: centerX, y: cursorY + metrics.nameFontPx * scale * 0.18),
            fontPx: metrics.nameFontPx, tracking: metrics.nameFontPx * style.labelTrackingEm * scale,
            color: style.labelTextColor, in: surface
        )

        if let subtitle = identity.subtitle {
            cursorY -= style.labelDetailGapPx * scale + metrics.strapFontPx * scale
            drawShadowedText(
                subtitle, anchor: CGPoint(x: centerX, y: cursorY + metrics.strapFontPx * scale * 0.18),
                fontPx: metrics.strapFontPx, tracking: metrics.strapTracking,
                color: style.labelDetailColor, in: surface
            )
        }

        guard identity.photoCount > 1 else { return }
        let radius = style.deckDotRadiusPx * scale
        drawProgressDots(
            count: identity.photoCount, current: identity.focusIndex,
            centerX: centerX, centerY: rect.minY + radius * style.deckDotActiveScale, in: surface
        )
    }

    /// The photo-count indicator: a filled accent dot for the photo on screen,
    /// dim dots for the rest. Deliberately not a control — a film has no taps —
    /// so it is small, low-contrast and never grows a track or a chevron.
    private func drawProgressDots(
        count: Int, current: Int, centerX: CGFloat, centerY: CGFloat, in surface: RenderSurface
    ) {
        let context = surface.context
        let radius = style.deckDotRadiusPx * surface.scale
        let spacing = radius * style.deckDotSpacingMultiple
        var dotX = centerX - spacing * CGFloat(count - 1) / 2
        for dot in 0..<count {
            let isOn = dot == current
            let drawn = isOn ? radius * style.deckDotActiveScale : radius
            context.setFillColor(isOn ? style.deckDotOnColor : style.deckDotOffColor)
            context.fillEllipse(in: CGRect(
                x: dotX - drawn, y: centerY - drawn, width: drawn * 2, height: drawn * 2
            ))
            dotX += spacing
        }
    }

    // MARK: - Text helpers

    func textWidth(_ text: String, fontPx: CGFloat, tracking: CGFloat = 0, in surface: RenderSurface) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(
            line(text, fontPx: fontPx, scale: surface.scale, tracking: tracking), nil, nil, nil
        ))
    }

    func drawCenteredText(
        _ text: String, centerX: CGFloat, baselineY: CGFloat, fontPx: CGFloat, color: CGColor,
        tracking: CGFloat = 0, in surface: RenderSurface
    ) {
        let width = textWidth(text, fontPx: fontPx, tracking: tracking, in: surface)
        drawText(
            text, at: CGPoint(x: centerX - width / 2, y: baselineY),
            fontPx: fontPx, color: color, tracking: tracking, in: surface
        )
    }

    /// Centred type with the prototype's `text-shadow` under it — the only thing
    /// keeping unplated white type legible over a bright photograph. `anchor` is
    /// (centre x, baseline y).
    func drawShadowedText(
        _ text: String, anchor: CGPoint, fontPx: CGFloat, tracking: CGFloat,
        color: CGColor, in surface: RenderSurface
    ) {
        surface.context.saveGState()
        surface.context.setShadow(
            offset: CGSize(width: 0, height: -style.labelShadowOffsetPx * surface.scale),
            blur: style.labelShadowBlurPx * surface.scale, color: style.labelShadowColor
        )
        drawCenteredText(
            text, centerX: anchor.x, baselineY: anchor.y, fontPx: fontPx,
            color: color, tracking: tracking, in: surface
        )
        surface.context.restoreGState()
    }

    func drawText(
        _ text: String, at origin: CGPoint, fontPx: CGFloat, color: CGColor,
        tracking: CGFloat = 0, in surface: RenderSurface
    ) {
        surface.context.saveGState()
        surface.context.textPosition = origin
        CTLineDraw(line(text, fontPx: fontPx, scale: surface.scale, color: color, tracking: tracking), surface.context)
        surface.context.restoreGState()
    }

    private func line(
        _ text: String, fontPx: CGFloat, scale: CGFloat, color: CGColor? = nil, tracking: CGFloat = 0
    ) -> CTLine {
        var attributes: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontPx * scale, nil)
        ]
        if let color { attributes[kCTForegroundColorAttributeName] = color }
        // CSS `letter-spacing` — CoreText's kern attribute is the same idea:
        // extra advance after every glyph, including the last.
        if abs(tracking) > 0.01 { attributes[kCTKernAttributeName] = tracking }
        let attributed = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attributes as CFDictionary)
        return CTLineCreateWithAttributedString(attributed!)
    }
}
