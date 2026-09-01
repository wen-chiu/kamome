import CoreGraphics
@testable import Kamome
import KamomeConfig
// `@testable` for `LinearTimeline.path` — the arc windows, so the audit can name
// the crossing's own share of the budget rather than leave it to arithmetic.
@testable import KamomeExportEngine
import XCTest

/// **Where an export's snapshots actually go** (2026-08-15).
///
/// Export time is snapshot-bound — 0.72–1.55 s per snapshot on device
/// (decisions.md 2026-08-15) — so "how many snapshots does this film take?" *is*
/// the export budget. It had never been counted. The per-snapshot figures in
/// `CLAUDE.md` were derived as `frames ÷ keyframe_interval_frames`, which
/// silently assumes one snapshot every interval for the whole film. It is not:
/// `RecapRenderLoop` snapshots the **opening** every frame.
///
/// This harness counts them through the shipped loop, over a real fixture trip.
/// It changes nothing — what a coarser interval costs is cross-fade quality, and
/// that is a product judgement made against renders, not a config edit.
///
///   TEST_RUNNER_KAMOME_SNAPSHOT_AUDIT=miyakojima \
///   xcodebuild -scheme Kamome test -destination '…' \
///     -only-testing:KamomeTests/RecapSnapshotBudgetTests
///
/// Offline by default (`base_url` empty ⇒ every leg inferred, worst case for
/// geometry). Set `TEST_RUNNER_KAMOME_ROUTING_BASE_URL` to price a routed film.
final class RecapSnapshotBudgetTests: XCTestCase {
    /// Counts provider hits. Every hit is one `MKMapSnapshotter` fetch on the
    /// shipped Apple-Maps path, so this number times the per-snapshot cost is
    /// the export. Lock-guarded: the loop prefetches concurrently.
    private final class CountingFlatProvider: MapRenderer {
        private let inner = FlatSnapshotProvider()
        private let lock = NSLock()
        private var hits = 0

        var capabilities: MapRendererCapabilities { inner.capabilities }
        var count: Int { lock.withLock { hits } }

        func snapshot(
            _ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int
        ) async throws -> MapSnapshot {
            lock.withLock { hits += 1 }
            return try await inner.snapshot(frame, map: map, widthPx: widthPx, heightPx: heightPx)
        }
    }

    private struct Scene {
        let timeline: LinearTimeline
        let compositor: FrameCompositor
        let config: TrackingConfig.Export
    }

    func testSnapshotBudgetSplitByOpeningAndBody() async throws {
        let fixture = ProcessInfo.processInfo.environment["KAMOME_SNAPSHOT_AUDIT"] ?? ""
        try XCTSkipUnless(
            !fixture.isEmpty,
            "Measurement harness — set KAMOME_SNAPSHOT_AUDIT to a fixture name (e.g. miyakojima)."
        )

        let shipped = try await scene(fixture: fixture)
        let openingFrames = Int((shipped.timeline.openingS * Double(shipped.config.fps)).rounded())
        print(String(
            format: "KAMOME_SNAPSHOT_AUDIT %@ — %.1fs film · %d frames · opening %.2fs (%d frames, %.1f%%)",
            fixture, shipped.timeline.durationS, shipped.timeline.frameCount,
            shipped.timeline.openingS, openingFrames,
            100 * Double(openingFrames) / Double(max(shipped.timeline.frameCount, 1))
        ))

        // The opening's own cost, measured by stopping the shipped loop at the
        // boundary. Overcounts by at most `prefetchDepth + 2` keyframes already
        // requested for the body — small, and named rather than hidden.
        let opening = try await fetches(shipped, stoppingAfter: openingFrames)
        let total = try await fetches(shipped)
        report(label: "crop-scaled stations", opening: opening, total: total, scene: shipped)

        try await reportStations(shipped, openingFrames: openingFrames, total: total)

        XCTAssertGreaterThan(total, 0, "the audit fetched no snapshots")
    }

    /// Where the stations fall, three ways, so a saving can be attributed rather
    /// than admired in aggregate.
    private func reportStations(_ shipped: Scene, openingFrames: Int, total: Int) async throws {
        // attributed rather than admired in aggregate. The arc's seconds are the
        // crossing's own; the opening is everything before `openingS`; the rest
        // is body. Counted off the plan rather than the loop because the plan is
        // pure and the loop's answer must equal it — asserted below.
        let plan = RecapRenderLoop(
            timeline: shipped.timeline, compositor: shipped.compositor,
            provider: CountingFlatProvider(), config: shipped.config
        ).stations
        let arcWindows = shipped.timeline.path.arcWindowsS
        func inArc(_ station: RecapSnapshotStations.Station) -> Bool {
            let start = Double(station.frames.lowerBound) / Double(shipped.config.fps)
            return arcWindows.contains { $0.contains(start) }
        }
        let openingStations = plan.filter { $0.frames.lowerBound < openingFrames }.count
        let arcStations = plan.filter { $0.frames.lowerBound >= openingFrames && inArc($0) }.count
        print(String(
            format: "KAMOME_SNAPSHOT_AUDIT   stations: %d = %d opening + %d arc + %d body · "
                + "longest %d frames · shortest %d frames",
            plan.count, openingStations, arcStations,
            plan.count - openingStations - arcStations,
            plan.map(\.frames.count).max() ?? 0, plan.map(\.frames.count).min() ?? 0
        ))
        // Fetches may be **fewer** than stations and never more: two stations that
        // resolve to the same camera and map are the same picture, and the value
        // cache pays for it once. Hold-aware splitting (2026-09-01) made that
        // common — a stop beat's own station often repeats a framing the film has
        // already held. More fetches than stations would mean the cache and the
        // plan disagree about what one picture is, which is the real failure.
        XCTAssertLessThanOrEqual(
            total, plan.count,
            "the loop fetched more snapshots than there are stations"
        )
        if total < plan.count {
            print(String(
                format: "KAMOME_SNAPSHOT_AUDIT   %d of %d stations shared a fetch (identical camera and map)",
                plan.count - total, plan.count
            ))
        }
    }

    /// **The cost/sharpness curve `snapshot_station_max_magnification` buys**,
    /// so the value is chosen from a table rather than from `Docs/camera-arcs.md`
    /// §7's "roughly every 1.5× of zoom", which was reasoned for an *arc* and had
    /// never been priced against a body camera that pans.
    ///
    /// 1.0 is the interval-1 reference: one station per camera value, identity
    /// transform, pixel-identical to snapshotting every frame. Everything above
    /// it trades sharpness for snapshots, and only a render says how much
    /// sharpness — this half is the cost half.
    func testWhatEachStationBudgetCosts() async throws {
        let fixture = ProcessInfo.processInfo.environment["KAMOME_SNAPSHOT_AUDIT"] ?? ""
        try XCTSkipUnless(!fixture.isEmpty, "Measurement harness — set KAMOME_SNAPSHOT_AUDIT.")
        let shipped = try await scene(fixture: fixture)
        let openingFrames = Int((shipped.timeline.openingS * Double(shipped.config.fps)).rounded())
        let arcWindows = shipped.timeline.path.arcWindowsS

        for budget in [1.0, 1.02, 1.05, 1.1, 1.2, 1.35, 1.5, 2.0] {
            let config = shipped.config.withSnapshotStations(
                maxMagnification: budget, padding: budget == 1 ? 1 : shipped.config.snapshotStationPadding
            )
            let plan = RecapRenderLoop(
                timeline: shipped.timeline, compositor: shipped.compositor,
                provider: CountingFlatProvider(), config: config
            ).stations
            let opening = plan.filter { $0.frames.lowerBound < openingFrames }.count
            let arc = plan.filter { station in
                let start = Double(station.frames.lowerBound) / Double(shipped.config.fps)
                return station.frames.lowerBound >= openingFrames && arcWindows.contains { $0.contains(start) }
            }.count
            print(String(
                format: "KAMOME_STATION_CURVE %@ · magnification %.2f · %4d snapshots = %3d opening + %3d arc + %3d body",
                fixture, budget, plan.count, opening, arc, plan.count - opening - arc
            ))
        }
    }

    // MARK: - Measurement

    /// Runs the **shipped** `RecapRenderLoop` and returns how many snapshots it
    /// asked for. Nothing is modelled or re-derived: a count that disagreed with
    /// the loop would be worthless, and the loop's caching, eviction and
    /// prefetching are exactly what decides the number.
    private func fetches(_ scene: Scene, stoppingAfter limit: Int? = nil) async throws -> Int {
        let provider = CountingFlatProvider()
        let loop = RecapRenderLoop(
            timeline: scene.timeline, compositor: scene.compositor,
            provider: provider, config: scene.config
        )
        try await loop.renderFrames { frame, _ in
            guard let limit else { return true }
            return frame + 1 < limit
        }
        return provider.count
    }

    /// One line per configuration, with the number `CLAUDE.md` would have
    /// quoted printed beside the measured one — so the gap is visible rather
    /// than argued about.
    private func report(label: String, opening: Int, total: Int, scene: Scene) {
        let body = max(total - opening, 0)
        let share = 100 * Double(opening) / Double(max(total, 1))
        let derived = scene.timeline.frameCount / max(scene.config.keyframeIntervalFrames, 1)
        print(String(
            format: "KAMOME_SNAPSHOT_AUDIT   %@: %d snapshots = %d opening + %d body · "
                + "opening is %.0f%% of the budget · frames ÷ interval would have said %d",
            label, total, opening, body, share, derived
        ))
    }

    // MARK: - Scene

    /// The same composition `RecapModel` performs, minus the map: `establishing`
    /// is nil, which is the **shipped** path since MapLibre was parked
    /// (decisions.md 2026-08-15) — no tiles are installed, so every device
    /// export frames from the trip's own bounds and renders on Apple's map.
    private func scene(fixture: String) async throws -> Scene {
        let baseURL = ProcessInfo.processInfo.environment["KAMOME_ROUTING_BASE_URL"] ?? ""
        // **The crossing fixture has to be routed by the sea provider or this
        // prices the wrong film** (2026-08-30). With routing disabled nothing is
        // established about any leg, so the crossing is not a crossing, no arc is
        // built, and the audit reports a body that never fine-samples — measured
        // at 34 body snapshots against the 214 the same fixture costs once the
        // crossing exists. A budget for a feature that was switched off is worse
        // than no budget.
        let (trip, config) = try await RecapDemoFilmTests.importedRecap(
            named: fixture, baseURL: baseURL, reconstructor: UnroutableSeaProvider.forFixture(fixture)
        )
        let timeline = try XCTUnwrap(
            LinearTimeline(trip: trip, config: config, establishing: nil),
            "the fixture produced no timeline"
        )
        // Pinned, not inherited: this bench counts snapshots and its numbers must
        // not move because someone toggled the simulator's appearance. Light is
        // the shipped Apple Maps base it has always measured against.
        let style = RecapStyle.modernMinimal(.light).withEndCard(config.endCardStyle)
        return Scene(
            timeline: timeline,
            compositor: FrameCompositor(
                timeline: timeline,
                subject: VehicleSubjectRenderer.make(style: style, config: config),
                overlay: RecapOverlayRenderer(style: style, resolver: NoPhotoResolver()),
                style: style,
                widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
            ),
            config: config
        )
    }

    /// Deck bitmaps are irrelevant to the snapshot count and would only add
    /// decode time to a measurement that is about the base map.
    private struct NoPhotoResolver: RecapPhotoResolving {
        func image(for ref: PhotoRef, targetPx: Int) -> CGImage? { nil }
    }
}
