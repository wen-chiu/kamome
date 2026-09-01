import CoreGraphics
import Foundation

/// The base map behind one frame, in one of two forms.
///
/// **Reprojected** (`station:reprojection:`) is what the render loop produces:
/// one station snapshot, translated and scaled onto this frame's camera
/// (`Docs/camera-arcs.md` §7). The frame is geometrically exact, so the
/// projection is exact too and the trail and marker sit *on* the map.
///
/// **Cross-faded** (`current:previous:blend:`) is the older form, kept because
/// the still harnesses pass a single snapshot through it (`blend` 1, no
/// `previous`) and because `RecapFrameTests` asserts the blend arithmetic
/// itself. ⚠️ Two snapshots at two *different* cameras must not be blended
/// through it: that is Chiu's P0 — the 殘影 is the double image and the 晃動 is
/// it snapping forward twice a second (`HANDOFF.md` 2026-08-30 finding 1). The
/// loop no longer does it; the type still can, so the way to keep that honest is
/// that nothing in the shipping path constructs it that way any more.
public struct RecapBackground {
    public let current: MapSnapshot
    public let previous: MapSnapshot?
    public let blend: Double
    /// How `current` is placed on this frame. `nil` draws it 1:1 into the frame,
    /// which is the still harnesses' case: a snapshot taken at exactly this
    /// camera needs no transform.
    public let reprojection: SnapshotReprojection?

    public init(current: MapSnapshot, previous: MapSnapshot? = nil, blend: Double = 1) {
        self.current = current
        self.previous = previous
        self.blend = min(max(blend, 0), 1)
        reprojection = nil
    }

    /// One station serving this frame by reprojection — no second snapshot, and
    /// therefore no blend to be wrong about.
    public init(station: MapSnapshot, reprojection: SnapshotReprojection) {
        current = station
        previous = nil
        blend = 1
        self.reprojection = reprojection
    }

    func point(lat: Double, lon: Double) -> CGPoint {
        let currentPoint = current.point(lat: lat, lon: lon)
        if let reprojection { return reprojection.map(currentPoint) }
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
    /// What crosses a leg with no road. **nil is a real answer** — a film whose
    /// caller supplied none draws its own vehicle across the crossing, which is
    /// exactly the behaviour every film had before crossings existed, rather
    /// than nothing at all.
    private let crossingSubject: SubjectRenderer?
    private let overlay: OverlayRenderer
    private let style: RecapStyle
    private let widthPx: Int
    private let heightPx: Int
    private let scale: CGFloat

    /// `style` supplies only the frame-wide atmosphere (grade, vignette) — the
    /// renderers carry their own copy for the things they draw. Defaults to the
    /// neutral style, i.e. no atmosphere, which is what the golden-frame gates
    /// render against.
    public init(
        timeline: LinearTimeline,
        subject: SubjectRenderer,
        overlay: OverlayRenderer,
        style: RecapStyle = RecapStyle(),
        widthPx: Int,
        heightPx: Int,
        crossingSubject: SubjectRenderer? = nil
    ) {
        self.timeline = timeline
        self.subject = subject
        self.crossingSubject = crossingSubject
        self.overlay = overlay
        self.style = style
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
        if let reprojection = background.reprojection {
            // The station's whole image, placed so its contained sub-rectangle
            // lands on the frame. Clipped because the rest of it hangs off every
            // edge by design and resampling what will not be seen is waste.
            context.saveGState()
            context.clip(to: frameRect)
            context.interpolationQuality = .high
            context.draw(background.current.image, in: reprojection.destinationRect)
            context.restoreGState()
        } else if let previous = background.previous, background.blend < 1 {
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
        // The crossing's narrator, when there is one. The choice is made here —
        // the last place before pixels — because which sprite means what is a
        // rendering decision, while *that* this stretch is being crossed is a
        // fact about the journey the timeline already established.
        let subjectState = timeline.subjectState(atTime: time)
        let drawing = subjectState.role == .crossing ? (crossingSubject ?? subject) : subject
        drawing.render(subjectState, camera: camera, into: surface)
        for content in contents where !Self.drawsBelowSubject(content) {
            overlay.render(content, camera: camera, into: surface)
        }
        drawAtmosphere(in: context, rect: frameRect)

        guard let image = context.makeImage() else { throw RenderError() }
        return image
    }

    /// Grade then vignette, over the finished frame — so map, trail, subject and
    /// overlays all sit inside one atmosphere instead of the chrome floating
    /// above it. Both are no-ops unless the theme opts in.
    private func drawAtmosphere(in context: CGContext, rect: CGRect) {
        if style.gradeColor.alpha > 0.001 {
            context.setFillColor(style.gradeColor)
            context.fill(rect)
        }
        guard style.vignetteStrength > 0.001,
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return }
        let clear = style.vignetteColor.copy(alpha: 0) ?? style.vignetteColor
        let edge = style.vignetteColor.copy(alpha: style.vignetteStrength) ?? style.vignetteColor
        guard let gradient = CGGradient(
            colorsSpace: space, colors: [clear, clear, edge] as CFArray,
            locations: [0, style.vignetteInnerRadius, 1]
        ) else { return }
        // A radial ramp out to the frame's half-diagonal, squashed into the
        // frame's aspect so the darkening reaches every corner evenly.
        let halfWidth = rect.width / 2, halfHeight = rect.height / 2
        context.saveGState()
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: halfWidth / halfHeight, y: 1)
        context.drawRadialGradient(
            gradient, startCenter: .zero, startRadius: 0,
            endCenter: .zero, endRadius: sqrt(halfHeight * halfHeight + halfHeight * halfHeight),
            options: [.drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    /// The route trail draws beneath the subject; the label, deck, and chrome
    /// draw above it. Z-order is a rendering concern, so it lives here, not on
    /// the style-independent `OverlayContent`.
    private static func drawsBelowSubject(_ content: OverlayContent) -> Bool {
        if case .routeReveal = content { return true }
        return false
    }
}
