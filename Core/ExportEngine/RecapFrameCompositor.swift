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
    public var headDotColor = CGColor(srgbRed: 1.0, green: 0.29, blue: 0.27, alpha: 1)
    public var cardColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96)
    public var cardTextColor = CGColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1)
    public var badgeColor = CGColor(srgbRed: 0.13, green: 0.45, blue: 0.95, alpha: 1)
    public var badgeTextColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

    public var routeWidthPx: CGFloat = 14
    public var headDotRadiusPx: CGFloat = 22
    public var cardMarginPx: CGFloat = 48
    public var cardHeightPx: CGFloat = 280
    public var cardCornerPx: CGFloat = 32
    public var cardPaddingPx: CGFloat = 28
    public var nameFontPx: CGFloat = 52
    public var badgeFontPx: CGFloat = 34
    public var badgeHeightPx: CGFloat = 56
    public var titleFontPx: CGFloat = 72
    public var subtitleFontPx: CGFloat = 40
    public var statFontPx: CGFloat = 44
    public var qrSidePx: CGFloat = 320

    public init() {}
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
    public struct StopCard {
        public let name: String
        public let dayLabel: String
        public let photo: CGImage?

        public init(name: String, dayLabel: String, photo: CGImage? = nil) {
            self.name = name
            self.dayLabel = dayLabel
            self.photo = photo
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
    let scale: CGFloat

    /// `stopCards[i]` matches stop index `i` as passed to `CameraPath`.
    /// Title/end events with nil content are skipped, so callers without
    /// chrome yet (previews) render route-only frames.
    public init(
        path: CameraPath,
        events: [OverlayEvent],
        stopCards: [StopCard],
        titleCard: TitleCard? = nil,
        endCard: EndCard? = nil,
        widthPx: Int,
        heightPx: Int,
        style: RecapStyle = RecapStyle()
    ) {
        self.path = path
        self.events = events
        self.stopCards = stopCards
        self.titleCard = titleCard
        self.endCard = endCard
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.style = style
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
        drawHeadDot(atTime: time, background: background, in: context)
        for event in OverlayTimeline.active(in: events, atTime: time) {
            draw(event: event, in: context)
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

    private func drawHeadDot(atTime time: Double, background: RecapBackground, in context: CGContext) {
        let position = path.position(atTime: time)
        let center = cgPoint(background.point(lat: position.lat, lon: position.lon))
        let radius = style.headDotRadiusPx * scale
        context.setFillColor(style.headDotColor)
        context.fillEllipse(
            in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        )
    }

    private func draw(event: OverlayEvent, in context: CGContext) {
        switch event.kind {
        case let .stopCard(stopIndex):
            guard stopCards.indices.contains(stopIndex) else { return }
            draw(card: stopCards[stopIndex], in: context)
        case .titleCard:
            guard let titleCard else { return }
            draw(titleCard: titleCard, in: context)
        case .endCard:
            guard let endCard else { return }
            draw(endCard: endCard, in: context)
        }
    }
}
