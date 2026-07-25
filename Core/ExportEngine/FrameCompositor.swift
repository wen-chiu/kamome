import CoreGraphics
import Foundation

/// The two keyframe snapshots a frame blends between. At `blend == 0` the
/// frame is pure `previous`; at 1, pure `current`. Overlay/subject geometry
/// projects through both snapshots and lerps the pixel positions, so the trail
/// and marker track the base map through the cross-fade instead of sliding over
/// it (§4.5 step 2).
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

/// Composites one video frame from the narrow-waist state streams
/// (render-layers refactor 2026-07-24). It owns no story or timing — it pulls
/// the `CameraFrame` / `SubjectState` / `OverlayContent` for `time` from the
/// injected `LinearTimeline` and hands them to the Layer 2/3 renderers over the
/// keyframe background. Pure CoreGraphics over the injected snapshot — with
/// `FlatSnapshotProvider` the whole pipeline is deterministic, which the
/// golden-frame gate tests rely on.
///
/// Z-order: the traveled trail draws beneath the moving subject (the subject
/// rides the head of its own trail), then the subject, then the stop label /
/// photo deck / chrome on top — so an enlarged deck photo blooms in front of
/// the vehicle. Which overlays sit under the subject is a rendering decision
/// (`drawsBelowSubject`), never the timeline's.
public struct FrameCompositor {
    public struct RenderError: Error {}

    private let timeline: LinearTimeline
    private let subject: SubjectRenderer
    private let overlay: OverlayRenderer
    private let widthPx: Int
    private let heightPx: Int
    private let scale: CGFloat

    public init(
        timeline: LinearTimeline,
        subject: SubjectRenderer,
        overlay: OverlayRenderer,
        widthPx: Int,
        heightPx: Int
    ) {
        self.timeline = timeline
        self.subject = subject
        self.overlay = overlay
        self.widthPx = widthPx
        self.heightPx = heightPx
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

        let camera = timeline.cameraFrame(atTime: time)
        // The projection carries the keyframe cross-fade blend, so the subject
        // and overlays track the map through a dolly/fade.
        let surface = RenderSurface(context: context, widthPx: widthPx, heightPx: heightPx, scale: scale) { lat, lon in
            background.point(lat: lat, lon: lon)
        }
        let contents = timeline.overlayContents(atTime: time)

        for content in contents where Self.drawsBelowSubject(content) {
            overlay.render(content, camera: camera, into: surface)
        }
        subject.render(timeline.subjectState(atTime: time), camera: camera, into: surface)
        for content in contents where !Self.drawsBelowSubject(content) {
            overlay.render(content, camera: camera, into: surface)
        }

        guard let image = context.makeImage() else { throw RenderError() }
        return image
    }

    /// The route trail draws beneath the subject; the label, deck, and chrome
    /// draw above it. Z-order is a rendering concern, so it lives here, not on
    /// the style-independent `OverlayContent`.
    private static func drawsBelowSubject(_ content: OverlayContent) -> Bool {
        if case .routeReveal = content { return true }
        return false
    }
}
