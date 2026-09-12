import CoreGraphics
@testable import Kamome
import KamomeExportEngine
import XCTest

/// **One finished frame of a follow-cam still** — split out of
/// `RecapFollowCamStillsTests` on 2026-09-12, which had reached the 400-line
/// lint ceiling, the same way `RecapDemoFilmSubstrate` was split from
/// `RecapDemoFilmTests`.
///
/// It exists because three call sites in that harness compose a frame the same
/// way, and one of the arguments is a licence obligation: the **map credit the
/// substrate declares** (ADR 2026-09-12). A review still rendered without it
/// would be a different frame from the one the app exports, which defeats the
/// purpose of judging from a still at all — so the credit is taken from the
/// renderer that drew the picture, exactly as `RecapRenderLoop` takes it.
///
/// The souvenir `.pmtiles` regions this harness renders are OpenStreetMap data,
/// so the provider is built with `RecapMapAttribution.openStreetMap` and this
/// hands whatever it declared to the compositor.
extension RecapFollowCamStillsTests {
    func still(
        _ compositor: FrameCompositor, atTime time: Double, of snapshot: MapSnapshot, on renderer: MapRenderer
    ) throws -> CGImage {
        try compositor.render(
            atTime: time, background: RecapBackground(current: snapshot),
            credit: renderer.capabilities.attribution
        )
    }
}
