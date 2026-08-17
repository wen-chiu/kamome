import CoreGraphics
import ImageIO
@testable import Kamome
import KamomeExportEngine
import UniformTypeIdentifiers
import XCTest

/// Renders **one stop** of a real imported trip — not the film. Manual review
/// harness, env-gated, never CI.
///
/// A stop's presentation is a still-frame question (does the photo dominate? does
/// the map still read around it? is the type a headline or an annotation?), and
/// answering it with a 90-second MP4 render costs minutes and settles nothing.
/// This takes the same pipeline the exporter uses — imported trip → OSRM
/// reconstruction → `LinearTimeline` → `FrameCompositor` over the real MapLibre
/// souvenir map (`RecapReviewScene`) — and writes the single frame where the
/// stop's photo deck is most open.
///
///   TEST_RUNNER_KAMOME_STOP_STILL=iceland \
///   TEST_RUNNER_KAMOME_OSRM_BASE_URL=http://127.0.0.1:5100 \
///   TEST_RUNNER_KAMOME_TILES_PATH=$HOME/kamome-osrm/tiles \
///   TEST_RUNNER_KAMOME_TERRAIN_PATH=$HOME/kamome-osrm/terrain \
///   TEST_RUNNER_KAMOME_STOP_PHOTOS=/path/to/jpegs \
///   TEST_RUNNER_KAMOME_RENDER_OUT=/path/to/out \
///   xcodebuild -scheme Kamome test -destination '…' \
///     -only-testing:KamomeTests/RecapStopStillTests
final class RecapStopStillTests: XCTestCase {
    /// One frame of the **opening title beat**, for confirming its layout before
    /// a full film is rendered against it (Chiu 2026-08-02).
    ///
    ///     TEST_RUNNER_KAMOME_TITLE_STILL=nz-real …
    func testRenderTitleStill() async throws {
        let fixture = ProcessInfo.processInfo.environment["KAMOME_TITLE_STILL"] ?? ""
        try XCTSkipUnless(!fixture.isEmpty, "Manual review harness — set KAMOME_TITLE_STILL.")
        let scene = try await RecapReviewScene.make(fixture: fixture)

        // Mid-title, where the card is fully up and the establishing shot has
        // settled — the frame a viewer actually reads.
        let peak = scene.config.titleCardS / 2
        let image = try await scene.frame(at: peak)

        let outDir = RecapReviewScene.outputDirectory()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("title-\(fixture).png")
        try write(image, to: url)
        print("KAMOME_TITLE_STILL \(url.path) — t=\(peak)s of a \(scene.timeline.durationS)s film")
    }

    func testRenderStopStill() async throws {
        let fixture = ProcessInfo.processInfo.environment["KAMOME_STOP_STILL"] ?? ""
        try XCTSkipUnless(
            !fixture.isEmpty,
            "Manual review harness — set KAMOME_STOP_STILL to a fixture name (e.g. iceland)."
        )
        let scene = try await RecapReviewScene.make(fixture: fixture)

        // The stop worth reviewing is the one that exercises the whole
        // composition: the most photos, so the deck stacks and the dots page, and
        // among ties the *latest*, so the distance readout has something to say —
        // the first stop of a trip is 0 km in and shows neither trail nor figure.
        let stop = try XCTUnwrap(
            scene.trip.stops.enumerated().filter { !$0.element.photos.isEmpty }
                .max { ($0.element.photos.count, $0.offset) < ($1.element.photos.count, $1.offset) }?.element,
            "the fixture has no stop with photos"
        )
        let peak = try XCTUnwrap(peakTime(scene.timeline, stop: stop), "the stop's deck never opens")
        let image = try await scene.frame(at: peak)

        let outDir = RecapReviewScene.outputDirectory()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("stop-\(fixture)-\(RecapReviewScene.variantSuffix).png")
        try write(image, to: url)
        print("KAMOME_STOP_STILL \(url.path) — \(stop.name) · \(stop.photos.count) photos · t=\(peak)s")
    }

    /// A **travelling** frame, for judging the subject itself.
    ///
    /// `testRenderStopStill` cannot answer that question: it renders the deck at
    /// its peak, and the subject is deliberately *parked away* during a stop
    /// scene so the pin can sit exactly where the journey paused (Chiu
    /// 2026-07-26). Every subject and every size therefore produced a
    /// byte-identical still — the frame simply has no vehicle in it.
    ///
    /// So this picks the moment the subject is fully present and the trail has
    /// something to show, which is what "is the car too big, and can you still
    /// read its heading?" needs.
    func testRenderSubjectStill() async throws {
        let fixture = HarnessEnv.value("KAMOME_SUBJECT_STILL") ?? ""
        try XCTSkipUnless(
            !fixture.isEmpty,
            "Manual review harness — set KAMOME_SUBJECT_STILL to a fixture name (e.g. miyakojima)."
        )
        let scene = try await RecapReviewScene.make(fixture: fixture)
        let time = try XCTUnwrap(travellingTime(scene.timeline), "the film never shows a moving subject")
        let image = try await scene.frame(at: time)

        let outDir = RecapReviewScene.outputDirectory()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("subject-\(fixture)-\(RecapReviewScene.variantSuffix).png")
        try write(image, to: url)

        let state = scene.timeline.subjectState(atTime: time)
        print(String(
            format: "KAMOME_SUBJECT_STILL %@ — t=%.1fs · heading %.0f° (%@ drawing) · emphasis %.2f",
            url.path, time, state.heading,
            SpriteDirection.nearest(toBearing: state.heading).rawValue, state.emphasis
        ))
    }

    /// The latest instant at which the subject is fully drawn — late enough that
    /// a trail exists behind it, and deterministic so a sweep compares like with
    /// like across sizes and subjects.
    private func travellingTime(_ timeline: LinearTimeline, dt: Double = 1.0 / 30) -> Double? {
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

    /// The instant this stop's deck is most open — the frame that shows the
    /// composition at full size rather than mid-bloom.
    private func peakTime(_ timeline: LinearTimeline, stop: RecapTrip.Stop, dt: Double = 1.0 / 30) -> Double? {
        var best: (time: Double, reveal: Double)?
        var time = 0.0
        while time <= timeline.durationS {
            for content in timeline.overlayContents(atTime: time) {
                guard case let .photoDeck(deck) = content,
                      deck.photos.first == stop.photos.first, deck.opacity > 0.99 else { continue }
                if deck.reveal > (best?.reveal ?? -1) { best = (time, deck.reveal) }
            }
            time += dt
        }
        return best?.time
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "PNG write failed")
    }
}
