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
        let url = outDir.appendingPathComponent("stop-\(fixture).png")
        try write(image, to: url)
        print("KAMOME_STOP_STILL \(url.path) — \(stop.name) · \(stop.photos.count) photos · t=\(peak)s")
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
