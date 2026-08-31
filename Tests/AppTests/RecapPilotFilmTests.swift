import AVFoundation
@testable import Kamome
// `@testable` for `LinearTimeline.holds` — the stop beats inside the encoded
// window, which `reportHolds` prints beside the clip.
@testable import KamomeExportEngine
import XCTest

/// Encodes the **opening stretch** of a real film — a motion check, env-gated,
/// never CI.
///
/// The point is that nothing is re-timed. The timeline is the shipped one, at its
/// shipped duration; only the *encode* stops early, so what plays back is exactly
/// the first N seconds of the real film. Compressing a 90-second film into 30 to
/// "preview" it would change the very thing a pacing question is asking about —
/// how long the opening holds before the journey starts, how long a stop dwells,
/// how fast the deck advances.
///
/// It also prints the beats it just encoded, in seconds, so a claim about pacing
/// can be checked against numbers rather than against a stopwatch on a video.
///
/// **`KAMOME_PILOT_START_S` moves the window off the opening** (2026-08-30).
/// The P0 is ghosting in the **body** of every film (`HANDOFF.md` 2026-08-30
/// finding 1), and the body is exactly the stretch this harness could not reach:
/// it always encoded from frame 0, so every clip anyone had watched was mostly
/// the one stretch that is already fine-sampled. Frames are re-indexed from zero
/// in the encode, so the clip plays from its first frame rather than opening on
/// a minute of black.
///
/// The snapshot count for the window is printed too, because the interval pair
/// the P0 asks for is only evidence if the cost of the naive fix is a number
/// rather than an argument.
///
///   TEST_RUNNER_KAMOME_PILOT_FILM=iceland \
///   TEST_RUNNER_KAMOME_PILOT_SECONDS=32 \
///   TEST_RUNNER_KAMOME_PILOT_START_S=40 \
///   TEST_RUNNER_KAMOME_KEYFRAME_INTERVAL=1 \
///   TEST_RUNNER_KAMOME_TILES_PATH=$HOME/kamome-osrm/tiles \
///   TEST_RUNNER_KAMOME_TERRAIN_PATH=$HOME/kamome-osrm/terrain \
///   TEST_RUNNER_KAMOME_STOP_PHOTOS=/path/to/jpegs \
///   TEST_RUNNER_KAMOME_RENDER_OUT=/path/to/out \
///   xcodebuild -scheme Kamome test -destination '…' \
///     -only-testing:KamomeTests/RecapPilotFilmTests
final class RecapPilotFilmTests: XCTestCase {
    /// Counts provider hits without changing what the loop asks for. Lock-guarded
    /// because the loop prefetches concurrently.
    private final class CountingProvider: MapRenderer {
        private let inner: MapRenderer
        private let lock = NSLock()
        private var hits = 0

        init(inner: MapRenderer) { self.inner = inner }

        var capabilities: MapRendererCapabilities { inner.capabilities }
        var count: Int { lock.withLock { hits } }

        func snapshot(
            _ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int
        ) async throws -> MapSnapshot {
            lock.withLock { hits += 1 }
            return try await inner.snapshot(frame, map: map, widthPx: widthPx, heightPx: heightPx)
        }
    }

    func testRenderPilotFilm() async throws {
        let fixture = ProcessInfo.processInfo.environment["KAMOME_PILOT_FILM"] ?? ""
        try XCTSkipUnless(
            !fixture.isEmpty,
            "Manual review harness — set KAMOME_PILOT_FILM to a fixture name (e.g. iceland)."
        )
        let seconds = ProcessInfo.processInfo.environment["KAMOME_PILOT_SECONDS"].flatMap(Double.init) ?? 30
        let startS = HarnessEnv.value("KAMOME_PILOT_START_S").flatMap(Double.init) ?? 0
        let scene = try await RecapReviewScene.make(fixture: fixture)
        let firstFrame = max(Int(startS * Double(scene.config.fps)), 0)
        let limit = min(scene.timeline.frameCount, firstFrame + Int(seconds * Double(scene.config.fps)))

        let outDir = RecapReviewScene.outputDirectory()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        // Named by what varies, so an interval pair does not overwrite itself —
        // the same rule `RecapReviewScene.variantSuffix` follows for stills.
        let url = outDir.appendingPathComponent(
            "pilot-\(fixture)-from\(Int(startS))s-interval\(scene.config.keyframeIntervalFrames).mp4"
        )
        try? FileManager.default.removeItem(at: url)

        let started = Date.now
        let written = try await encode(scene: scene, to: url, firstFrame: firstFrame, limit: limit, startS: startS)

        let sizeMB = Double(
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        ) / 1e6
        print(String(
            format: "KAMOME_PILOT_FILM %@ — %d/%d frames · %.1fs from %.1fs of a %.1fs film · %.1f MB "
                + "· rendered in %.0fs",
            url.path, written, scene.timeline.frameCount,
            Double(written) / Double(scene.config.fps), startS, scene.timeline.durationS,
            sizeMB, Date.now.timeIntervalSince(started)
        ))
        reportOpeningBeats(scene)
        reportHolds(scene, fromS: startS, toS: startS + Double(written) / Double(scene.config.fps))
        XCTAssertGreaterThan(written, 0, "the pilot encoded no frames")
    }

    /// Encodes `[firstFrame, limit)` and returns how many frames were written,
    /// printing the window's **snapshot count** on the way out.
    ///
    /// The count is taken through the shipped loop rather than modelled, for the
    /// reason `RecapSnapshotBudgetTests` exists: `frames ÷ interval` under-counts
    /// by ~3× wherever the loop fine-samples. Frames before the window are still
    /// composited, because the loop is sequential and its snapshot cache is
    /// stateful — skipping them would price a window no export ever reaches that
    /// way — and their snapshots are reported separately.
    private func encode(
        scene: RecapReviewScene, to url: URL, firstFrame: Int, limit: Int, startS: Double
    ) async throws -> Int {
        let encoder = try RecapVideoEncoder(
            outputURL: url, widthPx: scene.config.frameWidthPx, heightPx: scene.config.frameHeightPx,
            fps: scene.config.fps, bitrateMbps: scene.config.videoBitrateMbps
        )
        let counting = CountingProvider(inner: scene.provider)
        let loop = RecapRenderLoop(
            timeline: scene.timeline, compositor: scene.compositor,
            provider: counting, config: scene.config
        )
        var written = 0
        var before = 0
        try await loop.renderFrames { frame, image in
            guard frame < limit else { return false }
            guard frame >= firstFrame else {
                before = counting.count
                return true
            }
            // Re-indexed from zero: the clip is a window on the film, not the
            // film with a minute of nothing at the front.
            try encoder.append(image, frame: written)
            written += 1
            return true
        }
        try await encoder.finish()
        print(String(
            format: "KAMOME_PILOT_SNAPSHOTS %@ · window %.1fs–%.1fs · interval %d · %d snapshots in the window "
                + "(%d before it, %d total)",
            url.lastPathComponent, startS, startS + Double(written) / Double(scene.config.fps),
            scene.config.keyframeIntervalFrames, counting.count - before, before, counting.count
        ))
        return written
    }

    /// **The stop beats inside the encoded window.**
    ///
    /// Added 2026-08-30, with `KAMOME_PILOT_START_S`: once the window can sit
    /// anywhere in the film, "the beats it just encoded" stops meaning the
    /// opening's. It is also what a ghosting comparison needs — the mechanism in
    /// `HANDOFF.md` 2026-08-30 finding 1 predicts a double image **while
    /// travelling** and a clean picture **during a stop**, and that claim can only
    /// be checked against a clip if the stops' seconds are printed beside it.
    private func reportHolds(_ scene: RecapReviewScene, fromS: Double, toS: Double) {
        let inside = scene.timeline.holds
            .filter { $0.endS > fromS && $0.startS < toS }
            .map { String(format: "%.2f–%.2fs", max($0.startS, fromS), min($0.endS, toS)) }
        print("KAMOME_PILOT_HOLDS window \(String(format: "%.2f–%.2fs", fromS, toS)) contains "
            + (inside.isEmpty ? "no stop beat" : inside.joined(separator: ", ")))
    }

    /// The beats the encoded stretch contains, measured off the timeline. The
    /// opening's job is to hand over to the journey promptly: with a photo-bearing
    /// first stop the film presents *that stop* and the car arrives afterwards, so
    /// the gap that matters is opening-end → first stop, not opening-end → car.
    private func reportOpeningBeats(_ scene: RecapReviewScene, dt: Double = 1.0 / 30) {
        var firstStop: Double?
        var firstPhoto: Double?
        var carAppears: Double?
        var time = 0.0
        while time <= scene.timeline.durationS {
            for content in scene.timeline.overlayContents(atTime: time) {
                if case .stopLabel = content, firstStop == nil { firstStop = time }
                if case let .photoDeck(deck) = content, firstPhoto == nil, deck.opacity > 0.001 {
                    firstPhoto = time
                    firstStop = firstStop ?? time
                }
            }
            let subject = scene.timeline.subjectState(atTime: time)
            if carAppears == nil, subject.isVisible, subject.emphasis > 0.5 { carAppears = time }
            time += dt
        }
        print(String(
            format: "KAMOME_PILOT_BEATS opening ends %.2fs · first stop %.2fs · first photo %.2fs · car %.2fs",
            scene.timeline.openingS, firstStop ?? -1, firstPhoto ?? -1, carAppears ?? -1
        ))
    }
}
