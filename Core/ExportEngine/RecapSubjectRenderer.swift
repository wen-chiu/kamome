import CoreGraphics
import Foundation

/// What the moving subject looks like.
///
/// - `rasterSprite`: the bundled hero car as **eight drawings**, one per 45° of
///   heading. The renderer selects the nearest; it never rotates a bitmap, so the
///   3/4 perspective stays correct at every angle it can show.
/// - `marker`: a code-drawn vector shape (gull / scooter / bike), which *is*
///   rotated freely — a stroked vector survives that where shaded artwork does
///   not. Also the fallback if the sprite set fails to load.
public enum SubjectVisual {
    case rasterSprite([SpriteDirection: CGImage])
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

    /// Builds the renderer from the style tokens: the eight-way car sprite when
    /// the set loads, otherwise the vector marker.
    public static func make(style: RecapStyle) -> VehicleSubjectRenderer {
        if let set = RecapCarSprite.set {
            return VehicleSubjectRenderer(visual: .rasterSprite(set), lengthPx: style.carSpriteLengthPx)
        }
        return VehicleSubjectRenderer(
            visual: .marker(style.fallbackMarker, palette: VehicleMarker.Palette(
                fill: style.fallbackMarkerColor, accent: style.markerAccentColor, outline: style.markerOutlineColor
            )),
            lengthPx: style.fallbackMarkerLengthPx
        )
    }

    public func render(_ state: SubjectState, camera: CameraFrame, into surface: RenderSurface) {
        guard state.isVisible else { return }
        let center = surface.cgPoint(lat: state.lat, lon: state.lon)
        let screenBearing = VehicleMarker.screenRotationDegrees(
            heading: state.heading, bearing: camera.bearing
        )
        let size = lengthPx * surface.scale
        switch visual {
        case let .rasterSprite(set):
            let direction = SpriteDirection.nearest(toBearing: screenBearing)
            guard let sprite = set[direction] else { return }
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
