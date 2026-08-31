import CoreGraphics
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **The crop-scaling contract** (`Docs/camera-arcs.md` §7): one snapshot serves
/// a run of frames by reprojection, and it is correct exactly when it contains
/// every frame it serves.
///
/// Split out of `RecapFrameTests` on 2026-08-31 — that file is the render loop's
/// own suite and was at its length limit, and these assertions are about the
/// station planner rather than about compositing a frame.
final class RecapSnapshotStationsTests: RecapRenderTestCase {
    /// **The dedup must not swallow real movement** — the rule, restated for
    /// crop-scaling (`Arch.md` §4: a test whose case is unreachable is restated,
    /// not deleted).
    ///
    /// It used to assert *one snapshot per distinct camera value*, because the
    /// value cache was the mechanism and one snapshot could only ever serve one
    /// camera. Under `RecapSnapshotStations` one snapshot deliberately serves
    /// many distinct cameras, by reprojection — so that assertion now measures
    /// the mechanism's absence rather than the rule.
    ///
    /// The rule survives, and is stronger: movement is not swallowed because
    /// **every frame is served by a station whose footprint contains it**. A
    /// planner that ignored the 100 km leap would produce a station that does not
    /// contain the far cluster, and `SnapshotReprojection` refuses to build.
    /// Asserted on the real snapshots the loop fetched, not on the plan, so the
    /// provider's own projection is what is measured.
    ///
    /// The cost side is kept too, as the inequality it always really was: a
    /// moving film costs more than a held one, and never more than one snapshot
    /// per distinct camera value.
    func testMovingCameraIsCarriedByStationsThatContainEveryFrame() async throws {
        let config = exportConfig(targetDurationS: 2, fps: 5, keyframeIntervalFrames: 3)
        // Two clusters ~100 km apart: far beyond act_split_km, and once upon a
        // time two separate fixed frames with a cut between them.
        let jumped = [
            RecapCoordinate(lat: -32.00, lon: 115.75),
            RecapCoordinate(lat: -32.01, lon: 115.76),
            RecapCoordinate(lat: -33.00, lon: 115.80),
            RecapCoordinate(lat: -33.01, lon: 115.81)
        ]
        let trip = RecapTrip(
            route: jumped, stops: [], title: "Jump", subtitle: "",
            statsLines: [], callToAction: "", shareURL: ""
        )
        let timeline = try makeTimeline(trip, config: config)
        let compositor = makeCompositor(timeline)
        let provider = CountingProvider()
        let loop = RecapRenderLoop(timeline: timeline, compositor: compositor, provider: provider, config: config)

        let cameras = Set((0..<timeline.frameCount).map { timeline.cameraFrame(atTime: Double($0) / 5) })
        XCTAssertGreaterThan(cameras.count, 1, "the fixture must actually move the camera")

        try await loop.renderFrames { _, _ in true }

        // The plan partitions the film: every frame served exactly once, in
        // order, with no gap and no overlap.
        let plan = loop.stations
        XCTAssertEqual(
            plan.flatMap { Array($0.frames) }, Array(0..<timeline.frameCount),
            "the stations must cover every frame exactly once, in order"
        )
        // Containment, on the snapshots the provider actually produced. The
        // second bound is the other half of the contract: without it a planner
        // could "contain everything" in one enormous snapshot and still pass.
        for station in plan {
            let snapshot = try await provider.snapshot(
                station.camera, map: station.map,
                widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
            )
            for frame in station.frames {
                let magnification = try SnapshotReprojection(
                    station: snapshot, stationCamera: station.camera,
                    target: timeline.cameraFrame(atTime: Double(frame) / 5),
                    widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
                ).magnification
                XCTAssertGreaterThanOrEqual(magnification, 1 - 1e-6, "frame \(frame) is wider than its station")
                XCTAssertLessThanOrEqual(
                    magnification, config.snapshotStationMaxMagnification + 1e-6,
                    "frame \(frame) is magnified past snapshot_station_max_magnification"
                )
            }
        }
        XCTAssertLessThanOrEqual(
            plan.count, cameras.count,
            "a station may serve several camera values; never more snapshots than there are values"
        )
    }
}
