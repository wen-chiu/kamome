import CoreGraphics
import Foundation
@testable import Kamome
import KamomeExportEngine

/// **One rendered review frame, and the two rules for choosing and costing one**
/// — split out of `RecapReviewScene` so both files stay inside the size limits,
/// the same way `RecapDemoFilmSubstrate` already is.
struct RenderedFrame {
    let image: CGImage
    /// The base map's own wall time, excluding the compositor.
    let snapshotS: Double
    let camera: CameraFrame
}

extension RecapReviewScene {
    /// The same frame drawn on **a substrate other than this scene's own**, with
    /// the snapshot's wall time reported back (ADR 2026-09-09).
    ///
    /// Added for the substrate evaluation, which has to put four base maps under
    /// one camera frame: the comparison is only worth looking at if the camera,
    /// the timeline and the overlay are provably identical across the four, and
    /// the only honest way to guarantee that is to vary nothing but this argument.
    ///
    /// ⚠️ It does **not** re-resolve the appearance against `renderer`'s
    /// capabilities — the caller is responsible for handing in a substrate whose
    /// appearance matches the one this scene was built for, which is why
    /// `ReviewSubstrate.Substrate` carries its own.
    func frame(at time: Double, using renderer: MapRenderer) async throws -> RenderedFrame {
        let camera = timeline.cameraFrame(atTime: time)
        let started = Date()
        let background = try await renderer.snapshot(
            camera, map: MapState(), widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
        )
        let snapshotS = Date().timeIntervalSince(started)
        // **The credit the substrate declares, exactly as the render loop
        // supplies it** (ADR 2026-09-12). A review still that omitted it would
        // be judging a different frame than the film ships — which is the whole
        // reason this harness exists.
        let image = try compositor.render(
            atTime: time, background: RecapBackground(current: background),
            credit: renderer.capabilities.attribution
        )
        return RenderedFrame(image: image, snapshotS: snapshotS, camera: camera)
    }

    /// The latest instant at which the subject is fully drawn — late enough that
    /// a trail exists behind it, and deterministic so a sweep compares like with
    /// like across sizes, subjects and substrates.
    ///
    /// **Moved out of `RecapStopStillTests` on 2026-09-09**, when the substrate
    /// evaluation became its second caller. One implementation, for the reason
    /// `ReviewSubstrate`'s own doc comment gives at length: a rule with two copies
    /// has already proved it gets corrected in only one of them, and "the frame a
    /// review render judges" is exactly such a rule — two harnesses judging two
    /// different frames of one film is a silent difference.
    func travellingTime(dt: Double = 1.0 / 30) -> Double? {
        var visible: [Double] = []
        var time = timeline.openingS
        while time <= timeline.durationS {
            let state = timeline.subjectState(atTime: time)
            if state.isVisible, state.emphasis > 0.99 { visible.append(time) }
            time += dt
        }
        guard !visible.isEmpty else { return nil }
        // Two thirds of the way through the moving frames: past the first leg,
        // before the closing reveal.
        return visible[Int(Double(visible.count - 1) * 0.66)]
    }
}
