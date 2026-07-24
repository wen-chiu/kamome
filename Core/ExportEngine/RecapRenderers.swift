import CoreGraphics
import Foundation

// The three **renderer protocols** — the rendering side of the narrow waist
// (render-layers refactor 2026-07-24). Each consumes a state type and knows
// nothing about how that state was produced, so a VisualStyle can swap all
// three to change the look without touching story/timing. Each already has 2+
// real conformers coming (MapLibre/MapKit/Flat · car/gull · deck/label/chrome),
// so the abstraction is earned, not ceremony.
//
// (Defined here for review before the migration wires the conformers.)

// MARK: - Layer 1: MapRenderer

/// What a base-map renderer can do, declared explicitly so `CameraFrame`
/// consumers stop assuming. MapKit says `supportsBearing == false` rather than
/// silently accepting-and-ignoring a bearing.
public struct MapRendererCapabilities: Equatable {
    public let supportsBearing: Bool
    public let supportsHeadingUp: Bool

    public init(supportsBearing: Bool, supportsHeadingUp: Bool) {
        self.supportsBearing = supportsBearing
        self.supportsHeadingUp = supportsHeadingUp
    }
}

/// Layer 1: the base map. Renders a `CameraFrame` (+ `MapState`) into a
/// `MapSnapshot` whose projection travels with the image.
public protocol MapRenderer {
    var capabilities: MapRendererCapabilities { get }
    func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot
}

/// How the moving subject faces on screen — decoupled from which sprite it is,
/// so any (visual × mode) combination is valid (some just look better).
public enum SpriteMode: Equatable {
    /// Never rotates; relies on a heading-up map (the anime hero car).
    case heroUpright
    /// Rotates to `heading − bearing` (a top-down marker, the gull).
    case topDownRotating
}

/// The capability consumer: resolves a requested heading-up against what the
/// renderer supports, yielding both the camera decision (rotate the map?) and
/// the subject's `SpriteMode`. Nobody downstream assumes MapKit can rotate.
public struct FollowCamMode: Equatable {
    public let headingUp: Bool
    public let spriteMode: SpriteMode

    public init(headingUp: Bool, spriteMode: SpriteMode) {
        self.headingUp = headingUp
        self.spriteMode = spriteMode
    }

    public static func resolve(
        requestHeadingUp: Bool,
        _ capabilities: MapRendererCapabilities
    ) -> FollowCamMode {
        if requestHeadingUp, capabilities.supportsHeadingUp {
            return FollowCamMode(headingUp: true, spriteMode: .heroUpright)
        }
        return FollowCamMode(headingUp: false, spriteMode: .topDownRotating)
    }
}

// MARK: - Layers 2 & 3: what renderers draw onto

/// The drawing target handed to a subject/overlay renderer: the CG context plus
/// the geo→pixel projection + metrics it needs, so renderers never re-derive
/// mercator math. `project` is supplied by the compositor and carries the
/// keyframe cross-fade blend, so overlays track the map through a dolly/fade.
public struct RenderSurface {
    public let context: CGContext
    public let widthPx: Int
    public let heightPx: Int
    /// frameWidth / 1080 — design tokens are authored at the 1080 reference.
    public let scale: CGFloat
    private let project: (_ lat: Double, _ lon: Double) -> CGPoint

    public init(
        context: CGContext, widthPx: Int, heightPx: Int, scale: CGFloat,
        project: @escaping (_ lat: Double, _ lon: Double) -> CGPoint
    ) {
        self.context = context
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.scale = scale
        self.project = project
    }

    /// Geo → pixel in the snapshot's top-left origin.
    public func point(lat: Double, lon: Double) -> CGPoint { project(lat, lon) }

    /// Geo → the CGContext's bottom-left origin (all vector drawing goes here).
    public func cgPoint(lat: Double, lon: Double) -> CGPoint {
        let point = project(lat, lon)
        return CGPoint(x: point.x, y: CGFloat(heightPx) - point.y)
    }
}

/// Layer 2: draws the moving subject from its `SubjectState`. Style-specific;
/// owns the screen-space transform (rotate vs. upright, sprite vs. vector), but
/// never the motion or timing.
public protocol SubjectRenderer {
    func render(_ state: SubjectState, camera: CameraFrame, into surface: RenderSurface)
}

/// Layer 3: draws `OverlayContent`. Renders exactly what it is told and never
/// touches the camera — camera choreography lives in the timeline's camera track.
public protocol OverlayRenderer {
    func render(_ content: OverlayContent, camera: CameraFrame, into surface: RenderSurface)
}
