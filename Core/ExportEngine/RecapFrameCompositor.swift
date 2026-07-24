import CoreGraphics
import CoreText
import Foundation

/// Design constants for the recap frame (§4.5). These are visual identity,
/// not behavior tunables, so they live here rather than TrackingConfig.json
/// (spec §0 governs tunables; changing these should be a design decision in
/// code review, not a config edit). Sizes are in pixels at the 1080-wide
/// reference frame and scale linearly with frame width.
public struct RecapStyle {
    public var routeColor = CGColor(srgbRed: 0.13, green: 0.45, blue: 0.95, alpha: 1)
    public var cardColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96)
    public var cardTextColor = CGColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1)
    public var badgeColor = CGColor(srgbRed: 0.13, green: 0.45, blue: 0.95, alpha: 1)
    public var badgeTextColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    // Vehicle marker (§4.5 step 1). The moving subject: which sprite, how big,
    // and its body/glass/edge colors. Swap `vehicleMarker` to change the
    // subject without touching the compositor (car default; seagull/scooter/bike).
    public var vehicleMarker: VehicleMarker = .car
    public var markerColor = CGColor(srgbRed: 1.0, green: 0.29, blue: 0.27, alpha: 1)
    public var markerAccentColor = CGColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 0.92)
    public var markerOutlineColor = CGColor(srgbRed: 0.1, green: 0.11, blue: 0.14, alpha: 0.85)
    /// Marker length (nose-to-tail) at the 1080 reference; scales with width.
    public var vehicleMarkerLengthPx: CGFloat = 96
    /// Optional raster sprite for the moving subject (the cute anime car,
    /// injected by the app from a bundled asset — the core stays asset-free and
    /// deterministic). When set it replaces the vector `vehicleMarker`. In the
    /// heading-up chase cam (TravelBoast) it rides upright as a hero pose while
    /// the map rotates under it, so it is drawn without per-frame rotation;
    /// `markerImageHeightPx` is its displayed height at the 1080 reference.
    public var markerImage: CGImage?
    public var markerImageHeightPx: CGFloat = 360

    public var routeWidthPx: CGFloat = 14
    public var cardMarginPx: CGFloat = 48
    public var cardHeightPx: CGFloat = 280
    public var cardCornerPx: CGFloat = 32
    public var cardPaddingPx: CGFloat = 28
    public var nameFontPx: CGFloat = 52
    public var detailFontPx: CGFloat = 36
    public var cardDetailColor = CGColor(srgbRed: 0.45, green: 0.45, blue: 0.5, alpha: 1)
    public var badgeFontPx: CGFloat = 34
    public var badgeHeightPx: CGFloat = 56
    public var titleFontPx: CGFloat = 72
    public var subtitleFontPx: CGFloat = 40
    public var statFontPx: CGFloat = 44
    public var qrSidePx: CGFloat = 320

    // Photo deck (§5, Chiu 2026-07-23): the enlarged photo that blooms at a
    // stop. Peak hero width as a fraction of the frame; matte, dots, caption.
    public var deckPhotoWidthFraction: CGFloat = 0.64
    public var deckPhotoAspect: CGFloat = 1.25         // portrait card (h / w)
    public var deckMatteColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    public var deckMattePx: CGFloat = 14
    public var deckCornerPx: CGFloat = 28
    public var deckShadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35)
    public var deckCaptionFontPx: CGFloat = 40
    public var deckCaptionColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    public var deckDotRadiusPx: CGFloat = 7
    public var deckDotOnColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    public var deckDotOffColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4)

    // Stop label (§5 two-beat lead): a pin at the stop + a name pill above it,
    // anchored on the map (the reference's city label). Drawn by OverlayRenderer.
    public var labelPinColor = CGColor(srgbRed: 0.35, green: 0.85, blue: 0.95, alpha: 1)
    public var labelPinRingColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9)
    public var labelPinRadiusPx: CGFloat = 16
    public var labelPillColor = CGColor(srgbRed: 0.1, green: 0.12, blue: 0.16, alpha: 0.92)
    public var labelTextColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    public var labelDetailColor = CGColor(srgbRed: 0.7, green: 0.75, blue: 0.8, alpha: 1)
    public var labelFontPx: CGFloat = 46
    public var labelDetailFontPx: CGFloat = 32
    public var labelPillPaddingPx: CGFloat = 24
    public var labelPillGapPx: CGFloat = 28    // pin → pill vertical gap

    public init() {}
}

/// Photo-deck pacing (§5). A stop's dwell scales with its photo count so all
/// 3–8 photos get their `photoHoldS`; the compositor renders a grow → rotate →
/// shrink scale envelope over that window. Mirrors `export.deck_*`; the default
/// matches the shipped config so a default-constructed compositor still paces
/// sensibly.
public struct RecapDeck {
    public var photoHoldS: Double
    public var zoomS: Double
    /// The pin/label leads (spec §5, Chiu 2026-07-24 two-beat): it lands first
    /// at the follow span, then the camera dollies in and the photos bloom.
    public var labelLeadS: Double

    public init(photoHoldS: Double = 0.8, zoomS: Double = 0.5, labelLeadS: Double = 0.6) {
        self.photoHoldS = photoHoldS
        self.zoomS = zoomS
        self.labelLeadS = labelLeadS
    }

    /// Dwell for a stop showing `photoCount` deck photos: the label lead, then a
    /// grow-in and shrink-out (zoomS each) bracketing one `photoHoldS` slot per
    /// photo. At least one slot so a single-photo stop still reads.
    public func dwellS(photoCount: Int) -> Double {
        labelLeadS + 2 * zoomS + Double(max(1, photoCount)) * photoHoldS
    }
}

/// The two keyframe snapshots a frame blends between. At `blend == 0` the
/// frame is pure `previous`; at 1, pure `current`. Overlay geometry projects
/// through both snapshots and lerps the pixel positions, so the polyline
/// tracks the base map through the cross-fade instead of sliding over it.
public struct RecapBackground {
    public let current: MapSnapshot
    public let previous: MapSnapshot?
    public let blend: Double

    public init(current: MapSnapshot, previous: MapSnapshot? = nil, blend: Double = 1) {
        self.current = current
        self.previous = previous
        self.blend = min(max(blend, 0), 1)
    }

    func point(lat: Double, lon: Double) -> CGPoint {
        let currentPoint = current.point(lat: lat, lon: lon)
        guard let previous, blend < 1 else { return currentPoint }
        let previousPoint = previous.point(lat: lat, lon: lon)
        return CGPoint(
            x: previousPoint.x + (currentPoint.x - previousPoint.x) * blend,
            y: previousPoint.y + (currentPoint.y - previousPoint.y) * blend
        )
    }
}

/// §4.5 steps 2–3: composites one video frame. Pure CoreGraphics over the
/// injected snapshot — with `FlatSnapshotProvider` the whole pipeline is
/// deterministic, which the golden-frame gate tests rely on.
public struct RecapFrameCompositor {
    /// What a stop card shows during its hold (§4.5 step 3). Content is
    /// caller-supplied; the compositor never touches Photos or the DB.
    /// `detail` is the stop.kind line — walk visits get their walking
    /// duration ("步行 21 分鐘"), plain dwells pass nil; copy is formatted
    /// by the app layer so localization stays out of core.
    public struct StopCard {
        public let name: String
        public let dayLabel: String
        public let detail: String?
        /// The stop's deck photos (highlight first, §5). When non-empty the
        /// stop renders as an enlarging, rotating photo deck; when empty it
        /// falls back to the label-only bottom card (route-only / no-photo).
        public let photos: [CGImage]

        public init(name: String, dayLabel: String, detail: String? = nil, photos: [CGImage] = []) {
            self.name = name
            self.dayLabel = dayLabel
            self.detail = detail
            self.photos = photos
        }
    }

    /// Opening chrome (§4.5 step 4): trip name over dates + distance. All
    /// copy is caller-supplied so localization stays in the app layer.
    public struct TitleCard {
        public let title: String
        public let subtitle: String

        public init(title: String, subtitle: String) {
            self.title = title
            self.subtitle = subtitle
        }
    }

    /// Closing chrome (§4.5 step 4): stat lines plus the "Get this route"
    /// QR (`RecapQRCode.image(for:sidePx:)`) and its call-to-action copy.
    public struct EndCard {
        public let statsLines: [String]
        public let callToAction: String
        public let qrCode: CGImage?

        public init(statsLines: [String], callToAction: String, qrCode: CGImage? = nil) {
            self.statsLines = statsLines
            self.callToAction = callToAction
            self.qrCode = qrCode
        }
    }

    public struct RenderError: Error {}

    private let path: CameraPath
    private let events: [OverlayEvent]
    let stopCards: [StopCard]
    let titleCard: TitleCard?
    let endCard: EndCard?
    let widthPx: Int
    let heightPx: Int
    let style: RecapStyle
    let deck: RecapDeck
    let scale: CGFloat

    /// `stopCards[i]` matches stop index `i` as passed to `CameraPath`.
    /// Title/end events with nil content are skipped, so callers without
    /// chrome yet (previews) render route-only frames. `deck` sets the photo
    /// deck's pacing; the default matches the shipped config.
    public init(
        path: CameraPath,
        events: [OverlayEvent],
        stopCards: [StopCard],
        titleCard: TitleCard? = nil,
        endCard: EndCard? = nil,
        widthPx: Int,
        heightPx: Int,
        style: RecapStyle = RecapStyle(),
        deck: RecapDeck = RecapDeck()
    ) {
        self.path = path
        self.events = events
        self.stopCards = stopCards
        self.titleCard = titleCard
        self.endCard = endCard
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.style = style
        self.deck = deck
        scale = CGFloat(widthPx) / 1080
    }

    public func render(atTime time: Double, background: RecapBackground) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: widthPx,
                  height: heightPx,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw RenderError() }

        let frameRect = CGRect(x: 0, y: 0, width: widthPx, height: heightPx)
        if let previous = background.previous, background.blend < 1 {
            context.draw(previous.image, in: frameRect)
            context.setAlpha(CGFloat(background.blend))
            context.draw(background.current.image, in: frameRect)
            context.setAlpha(1)
        } else {
            context.draw(background.current.image, in: frameRect)
        }

        drawTraveledRoute(atTime: time, background: background, in: context)
        drawVehicleMarker(atTime: time, background: background, in: context)
        // Overlays draw over the marker so the enlarged deck photo can bloom in
        // front of the vehicle at a stop.
        for event in OverlayTimeline.active(in: events, atTime: time) {
            draw(event: event, atTime: time, in: context)
        }

        guard let image = context.makeImage() else { throw RenderError() }
        return image
    }

    /// Snapshot projections are top-left origin (MKMapSnapshotter convention);
    /// CGContext is bottom-left. All vector drawing converts through here.
    private func cgPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: CGFloat(heightPx) - point.y)
    }

    private func drawTraveledRoute(atTime time: Double, background: RecapBackground, in context: CGContext) {
        let prefix = path.routePrefix(atTime: time)
        guard prefix.count >= 2 else { return }
        context.setStrokeColor(style.routeColor)
        context.setLineWidth(style.routeWidthPx * scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: cgPoint(background.point(lat: prefix[0].lat, lon: prefix[0].lon)))
        for point in prefix.dropFirst() {
            context.addLine(to: cgPoint(background.point(lat: point.lat, lon: point.lon)))
        }
        context.strokePath()
    }

    /// The moving subject at its projected position (§4.5 step 1), drawn by the
    /// Layer-2 `SubjectRenderer`. The compositor supplies the state + camera and
    /// owns none of the marker's screen transform.
    private func drawVehicleMarker(atTime time: Double, background: RecapBackground, in context: CGContext) {
        let position = path.position(atTime: time)
        let cameraFrame = path.cameraFrame(atTime: time)
        let camera = CameraFrame(
            centerLat: cameraFrame.centerLat, centerLon: cameraFrame.centerLon,
            spanM: cameraFrame.spanM, bearing: cameraFrame.bearing
        )
        let state = SubjectState(lat: position.lat, lon: position.lon, heading: position.heading)
        subjectRenderer.render(state, camera: camera, into: renderSurface(background: background, in: context))
    }

    /// The subject renderer built from the style tokens (the anime sprite rides
    /// upright; the vector markers rotate to heading). Injected properly when
    /// the compositor consumes the timeline; built here during the bridge.
    private var subjectRenderer: SpriteSubjectRenderer {
        if let sprite = style.markerImage {
            return SpriteSubjectRenderer(visual: .sprite(sprite), mode: .heroUpright, sizePx: style.markerImageHeightPx)
        }
        return SpriteSubjectRenderer(
            visual: .marker(style.vehicleMarker, palette: VehicleMarker.Palette(
                fill: style.markerColor, accent: style.markerAccentColor, outline: style.markerOutlineColor
            )),
            mode: .topDownRotating,
            sizePx: style.vehicleMarkerLengthPx
        )
    }

    /// A `RenderSurface` whose projection carries the keyframe cross-fade blend.
    private func renderSurface(background: RecapBackground, in context: CGContext) -> RenderSurface {
        RenderSurface(context: context, widthPx: widthPx, heightPx: heightPx, scale: scale) { lat, lon in
            background.point(lat: lat, lon: lon)
        }
    }

    private func draw(event: OverlayEvent, atTime time: Double, in context: CGContext) {
        switch event.kind {
        case let .stopCard(stopIndex):
            guard stopCards.indices.contains(stopIndex) else { return }
            let card = stopCards[stopIndex]
            if card.photos.isEmpty {
                draw(card: card, in: context)
            } else {
                drawDeck(card: card, window: (event.startS, event.endS), atTime: time, in: context)
            }
        case .titleCard:
            guard let titleCard else { return }
            draw(titleCard: titleCard, in: context)
        case .endCard:
            guard let endCard else { return }
            draw(endCard: endCard, in: context)
        }
    }
}
