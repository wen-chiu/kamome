import CoreGraphics
import Foundation

/// What the moving subject looks like — a raster hero sprite (the anime car) or
/// a vector marker (the gull / the fallback car). Decoupled from `SpriteMode`,
/// so any (visual × mode) pairing is valid.
public enum SubjectVisual {
    case sprite(CGImage)
    case marker(VehicleMarker, palette: VehicleMarker.Palette)
}

/// Layer 2 (concrete): draws the moving subject from its `SubjectState`. It owns
/// only the screen-space transform (rotate to heading vs. ride upright) — never
/// the motion, which the timeline supplies. `sizePx` is the sprite's height or
/// the vector marker's nose-to-tail length, at the 1080 reference.
public struct SpriteSubjectRenderer: SubjectRenderer {
    public var visual: SubjectVisual
    public var mode: SpriteMode
    public var sizePx: CGFloat

    public init(visual: SubjectVisual, mode: SpriteMode, sizePx: CGFloat) {
        self.visual = visual
        self.mode = mode
        self.sizePx = sizePx
    }

    public func render(_ state: SubjectState, camera: CameraFrame, into surface: RenderSurface) {
        guard state.isVisible else { return }
        let center = surface.cgPoint(lat: state.lat, lon: state.lon)
        let rotation = mode == .topDownRotating
            ? VehicleMarker.screenRotationDegrees(heading: state.heading, bearing: camera.bearing)
            : 0
        let size = sizePx * surface.scale
        switch visual {
        case let .sprite(image):
            drawSprite(image, at: center, heightPx: size, rotationDegrees: rotation, in: surface.context)
        case let .marker(marker, palette):
            marker.draw(in: surface.context, at: center, lengthPx: size, rotationDegrees: rotation, colors: palette)
        }
    }

    /// Draws the hero sprite centered on the subject, native aspect preserved.
    /// A zero rotation (heroUpright) draws straight — byte-identical to an
    /// un-transformed `context.draw`.
    private func drawSprite(
        _ sprite: CGImage, at center: CGPoint, heightPx: CGFloat, rotationDegrees: Double, in context: CGContext
    ) {
        let width = heightPx * CGFloat(sprite.width) / CGFloat(sprite.height)
        let rect = CGRect(x: center.x - width / 2, y: center.y - heightPx / 2, width: width, height: heightPx)
        guard rotationDegrees != 0 else {
            context.draw(sprite, in: rect)
            return
        }
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: -rotationDegrees * .pi / 180)
        context.translateBy(x: -center.x, y: -center.y)
        context.draw(sprite, in: rect)
        context.restoreGState()
    }
}
