import CoreGraphics
import Foundation

// The three **renderer protocols** — the rendering side of the narrow waist
// (render-layers refactor 2026-07-24). Each consumes a state type and knows
// nothing about how that state was produced, so a VisualStyle can swap all
// three to change the look without touching story/timing. Each has 2+ real
// conformers (MapLibre/MapKit/Flat · car/gull/scooter/bike · deck/label/chrome),
// so the abstraction is earned, not ceremony.

// MARK: - Layer 1: MapRenderer

/// What a base-map renderer can do, declared explicitly so `CameraFrame`
/// consumers stop assuming. MapKit says `supportsBearing == false` rather than
/// silently accepting-and-ignoring a bearing.
public struct MapRendererCapabilities: Equatable {
    public let supportsBearing: Bool
    public let supportsHeadingUp: Bool
    /// The appearance this substrate is **locked to**, or nil if it renders in
    /// whichever one it is handed.
    ///
    /// Same rule as `supportsBearing`, one field down: a renderer says what it
    /// cannot do instead of silently ignoring the request. MapKit answers nil —
    /// it takes a `userInterfaceStyle` and honours it. The MapLibre souvenir map
    /// answers `.dark`, because its style sheet *is* dark
    /// (`Config/RecapThemes/modern-minimal.json`: `#08111A`, `#04070C`) and no
    /// trait makes it otherwise.
    ///
    /// **Why this is worth a field rather than a comment.** Without it, a device
    /// in light mode with tiles installed would render Kamome's light palette —
    /// an orange trail and a light-tuned grade — over a near-black map. That is
    /// the same class of defect as the halo (`a58942d`): a palette tuned for one
    /// base drawn over the other, invisible until someone looks at a finished
    /// film. It costs one `??` at the composition boundary to make impossible.
    public let fixedAppearance: RecapAppearance?

    public init(
        supportsBearing: Bool,
        supportsHeadingUp: Bool,
        fixedAppearance: RecapAppearance? = nil
    ) {
        self.supportsBearing = supportsBearing
        self.supportsHeadingUp = supportsHeadingUp
        self.fixedAppearance = fixedAppearance
    }

    /// The appearance a film will actually be rendered in on this substrate.
    ///
    /// Called once, at the composition boundary, before the style is built —
    /// never per frame. The requested value is the device's, captured at the tap;
    /// a substrate that cannot honour it overrides it, and the film's palette
    /// follows the answer rather than the request.
    public func appearance(honouring requested: RecapAppearance) -> RecapAppearance {
        fixedAppearance ?? requested
    }
}

/// Layer 1: the base map. Renders a `CameraFrame` (+ `MapState`) into a
/// `MapSnapshot` whose projection travels with the image.
public protocol MapRenderer {
    var capabilities: MapRendererCapabilities { get }
    func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot
}

// The map never rotates to follow the vehicle (product decision, Chiu
// 2026-07-25: a turning map hides the route's real shape and the distance
// covered, which is what a travel recap exists to show). The vehicle carries the
// heading instead. `export.follow_heading_up` therefore ships `false`, and
// `supportsHeadingUp` above survives only as the guard that stops a renderer
// which cannot rotate from being handed a bearing it would silently drop.
//
// This replaced a `FollowCamMode` type whose only job was choosing between the
// two orientations; with the choice settled there was no decision left to name.

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
