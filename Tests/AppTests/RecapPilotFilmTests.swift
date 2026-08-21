import AVFoundation
@testable import Kamome
import KamomeExportEngine
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
///   TEST_RUNNER_KAMOME_PILOT_FILM=iceland \
///   TEST_RUNNER_KAMOME_PILOT_SECONDS=32 \
///   TEST_RUNNER_KAMOME_TILES_PATH=$HOME/kamome-osrm/tiles \
///   TEST_RUNNER_KAMOME_TERRAIN_PATH=$HOME/kamome-osrm/terrain \
///   TEST_RUNNER_KAMOME_STOP_PHOTOS=/path/to/jpegs \
///   TEST_RUNNER_KAMOME_RENDER_OUT=/path/to/out \
///   xcodebuild -scheme Kamome test -destination '…' \
///     -only-testing:KamomeTests/RecapPilotFilmTests
final class RecapPilotFilmTests: XCTestCase {
    func testRenderPilotFilm() async throws {
        let fixture = ProcessInfo.processInfo.environment["KAMOME_PILOT_FILM"] ?? ""
        try XCTSkipUnless(
            !fixture.isEmpty,
            "Manual review harness — set KAMOME_PILOT_FILM to a fixture name (e.g. iceland)."
        )
        let seconds = ProcessInfo.processInfo.environment["KAMOME_PILOT_SECONDS"].flatMap(Double.init) ?? 30
        let scene = try await RecapReviewScene.make(fixture: fixture)
        let limit = min(scene.timeline.frameCount, Int(seconds * Double(scene.config.fps)))

        let outDir = RecapReviewScene.outputDirectory()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("pilot-\(fixture).mp4")
        try? FileManager.default.removeItem(at: url)

        let encoder = try RecapVideoEncoder(
            outputURL: url, widthPx: scene.config.frameWidthPx, heightPx: scene.config.frameHeightPx,
            fps: scene.config.fps, bitrateMbps: scene.config.videoBitrateMbps
        )
        let started = Date.now
        let loop = RecapRenderLoop(
            timeline: scene.timeline, compositor: scene.compositor,
            provider: scene.provider, config: scene.config
        )
        var written = 0
        try await loop.renderFrames { frame, image in
            guard frame < limit else { return false }
            try encoder.append(image, frame: frame)
            written += 1
            return true
        }
        try await encoder.finish()

        let sizeMB = Double(
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        ) / 1e6
        print(String(
            format: "KAMOME_PILOT_FILM %@ — %d/%d frames · %.1fs of a %.1fs film · %.1f MB · rendered in %.0fs",
            url.path, written, scene.timeline.frameCount,
            Double(written) / Double(scene.config.fps), scene.timeline.durationS,
            sizeMB, Date.now.timeIntervalSince(started)
        ))
        reportOpeningBeats(scene)
        XCTAssertGreaterThan(written, 0, "the pilot encoded no frames")
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
