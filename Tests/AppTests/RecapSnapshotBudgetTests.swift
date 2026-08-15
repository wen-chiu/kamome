import CoreGraphics
@testable import Kamome
import KamomeConfig
import KamomeExportEngine
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
/// geometry). Set `TEST_RUNNER_KAMOME_OSRM_BASE_URL` to price a routed film.
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
        report(label: "as-is (opening every frame)", opening: opening, total: total, scene: shipped)

        // The two alternatives Chiu is being asked to judge. Only the interval
        // changes; the film — duration, camera, stops, photos — is identical.
        for interval in [30] {
            let coarser = Scene(
                timeline: shipped.timeline, compositor: shipped.compositor,
                config: shipped.config.withKeyframeIntervalFrames(interval)
            )
            let coarseOpening = try await fetches(coarser, stoppingAfter: openingFrames)
            let coarseTotal = try await fetches(coarser)
            report(
                label: "keyframe_interval_frames = \(interval)",
                opening: coarseOpening, total: coarseTotal, scene: coarser
            )
        }

        XCTAssertGreaterThan(total, 0, "the audit fetched no snapshots")
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
        let baseURL = ProcessInfo.processInfo.environment["KAMOME_OSRM_BASE_URL"] ?? ""
        let (trip, config) = try await RecapDemoFilmTests.importedRecap(named: fixture, baseURL: baseURL)
        let timeline = try XCTUnwrap(
            LinearTimeline(trip: trip, config: config, establishing: nil),
            "the fixture produced no timeline"
        )
        let style = RecapStyle.modernMinimal.withEndCard(config.endCardStyle)
        return Scene(
            timeline: timeline,
            compositor: FrameCompositor(
                timeline: timeline,
                subject: VehicleSubjectRenderer.make(style: style),
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
