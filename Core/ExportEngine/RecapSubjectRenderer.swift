import CoreGraphics
import Foundation
import KamomeConfig

/// What the moving subject looks like.
///
/// The two raster cases are the two kinds of subject in
/// `Resources/Vehicles/README.md`, and they differ in what they mean rather than
/// only in how many files they have: a directional set expresses heading by
/// *which* drawing is chosen, while an omni mark deliberately expresses none.
///
/// - `rasterSprite`: eight drawings, one per 45° of heading; the renderer
///   selects the nearest and never rotates a bitmap.
/// - `omniSprite`: one drawing, never rotated and never heading-dependent.
/// - `marker`: a code-drawn vector shape, which *is* rotated freely — a stroked
///   vector survives that where shaded artwork does not. The last-resort
///   fallback when no artwork loads at all.
public enum SubjectVisual {
    case rasterSprite([SpriteDirection: CGImage])
    case omniSprite(CGImage)
    case marker(VehicleMarker, palette: VehicleMarker.Palette)
}

/// Layer 2 (concrete): draws the moving subject from its `SubjectState`. It owns
/// only the screen-space presentation — never the motion, which the timeline
/// supplies. `lengthPx` is the subject's longest on-screen dimension at the 1080
/// reference.
///
/// The map does not rotate (product decision, Chiu 2026-07-25: a turning map
/// hides the route's real shape and distance, which is the point of a travel
/// recap). So the *vehicle* carries the heading: screen rotation is
/// `heading − camera.bearing`, which with a north-up map is simply the travel
/// bearing.
public struct VehicleSubjectRenderer: SubjectRenderer {
    public var visual: SubjectVisual
    public var lengthPx: CGFloat

    public init(visual: SubjectVisual, lengthPx: CGFloat) {
        self.visual = visual
        self.lengthPx = lengthPx
    }

    /// Builds the renderer for the trip's chosen subject, sized from config —
    /// the shape every caller in the app and the harnesses uses.
    public static func make(
        style: RecapStyle, config: TrackingConfig.Export, subjectId: String? = nil
    ) -> VehicleSubjectRenderer {
        make(style: style, subjectId: subjectId, lengthPx: CGFloat(config.subjectLengthPx))
    }

    /// **The fallback chain is asked-for → car → marker**, and the order is the
    /// point: a car is a better failure than a dot, so a subject whose art is
    /// missing or half-drawn degrades to the shipped car rather than straight to
    /// a vector glyph. `VehicleCatalog.resolve` walks the first two; the marker
    /// is what is left when the resource bundle itself cannot be found.
    ///
    /// Size resolves in the order it is configured: the subject's own
    /// `length_px` override when the manifest declares one, otherwise the
    /// supplied `lengthPx`.
    ///
    /// `resolve` is injectable so a test can drive the marker fallback, which
    /// otherwise only fires when the app's own resource bundle cannot be found —
    /// a state no test can arrange. It is a closure rather than an optional
    /// result because "resolved to nothing" and "caller said nothing" are
    /// different answers and must not collapse into one nil.
    public static func make(
        style: RecapStyle,
        subjectId: String? = nil,
        lengthPx: CGFloat,
        resolve: (String?) -> (subject: VehicleSubject, artwork: SubjectArtwork)? = VehicleCatalog.resolve(id:)
    ) -> VehicleSubjectRenderer {
        guard let found = resolve(subjectId) else {
            return VehicleSubjectRenderer(
                visual: .marker(style.fallbackMarker, palette: VehicleMarker.Palette(
                    fill: style.fallbackMarkerColor, accent: style.markerAccentColor, outline: style.markerOutlineColor
                )),
                lengthPx: style.fallbackMarkerLengthPx
            )
        }
        let size = found.subject.lengthPx.map { CGFloat($0) } ?? lengthPx
        switch found.artwork {
        case let .directional(set):
            return VehicleSubjectRenderer(visual: .rasterSprite(set), lengthPx: size)
        case let .omni(image):
            return VehicleSubjectRenderer(visual: .omniSprite(image), lengthPx: size)
        }
    }

    /// `emphasis` is drawn as alpha, so the subject parks and pulls away rather
    /// than blinking out of existence at a stop (Chiu 2026-07-26).
    public func render(_ state: SubjectState, camera: CameraFrame, into surface: RenderSurface) {
        guard state.isVisible, state.emphasis > 0.001 else { return }
        let center = surface.cgPoint(lat: state.lat, lon: state.lon)
        let screenBearing = VehicleMarker.screenRotationDegrees(
            heading: state.heading, bearing: camera.bearing
        )
        let size = lengthPx * surface.scale
        surface.context.saveGState()
        surface.context.setAlpha(CGFloat(min(state.emphasis, 1)))
        defer { surface.context.restoreGState() }
        switch visual {
        case let .rasterSprite(set):
            let direction = SpriteDirection.nearest(toBearing: screenBearing)
            guard let sprite = set[direction] else { return }
            draw(sprite, at: center, longestSidePx: size, in: surface.context)
        case let .omniSprite(sprite):
            // No bearing is consulted at all: an omni mark stands for "you are
            // here" and must read the same whichever way the journey runs.
            draw(sprite, at: center, longestSidePx: size, in: surface.context)
        case let .marker(marker, palette):
            marker.draw(
                in: surface.context, at: center, lengthPx: size,
                rotationDegrees: screenBearing, colors: palette
            )
        }
    }

    /// Draws the selected sprite centered on the subject, native aspect
    /// preserved, its longest side scaled to `longestSidePx`. **Never rotated** —
    /// the heading is expressed by *which* of the eight drawings was chosen. All
    /// eight share a canvas size, so the car does not pulse as it turns.
    private func draw(
        _ sprite: CGImage, at center: CGPoint, longestSidePx: CGFloat, in context: CGContext
    ) {
        let imageWidth = CGFloat(sprite.width), imageHeight = CGFloat(sprite.height)
        let scale = longestSidePx / max(imageWidth, imageHeight)
        let width = imageWidth * scale, height = imageHeight * scale
        context.draw(sprite, in: CGRect(
            x: center.x - width / 2, y: center.y - height / 2, width: width, height: height
        ))
    }
}
