import CoreGraphics
import ImageIO
@testable import Kamome
import KamomeExportEngine
import UniformTypeIdentifiers
import XCTest

/// **The souvenir map, as stills** (ADR
/// 2026-10-29-the-film-inks-each-town-the-car-reaches, Draft). Manual review
/// harness, env-gated, never CI.
///
/// The last frame before the end card — the whole route held, every town the
/// car reached inked — drawn once per look Chiu is choosing between: the loop
/// and the underline, and on the dark map the trail's colour beside the
/// accent. One scene, one frame, one base map, so two stills differ in exactly
/// one thing.
///
///   TEST_RUNNER_KAMOME_INK_STILLS=new-zealand \
///   TEST_RUNNER_KAMOME_MAP_SUBSTRATE=liberty-fork-r6 \
///   TEST_RUNNER_KAMOME_MAP_APPEARANCE=dark \
///   TEST_RUNNER_KAMOME_GEOCODE_STOPS=1 \
///   TEST_RUNNER_KAMOME_RENDER_OUT=/path/to/out \
///   xcodebuild -scheme Kamome test -destination '…' \
///     -only-testing:KamomeTests/RecapInkedTownsStillsTests
final class RecapInkedTownsStillsTests: XCTestCase {
    func testRenderTheSouvenirMap() async throws {
        let fixture = HarnessEnv.value("KAMOME_INK_STILLS") ?? ""
        try XCTSkipUnless(!fixture.isEmpty, "Manual review harness — set KAMOME_INK_STILLS to a fixture name.")
        let scene = try await RecapReviewScene.make(fixture: fixture)
        let time = scene.timeline.durationS - scene.config.endCardS - 1 / Double(scene.config.fps)
        var variants: [(label: String, change: (inout RecapStyle) -> Void)] = [
            ("loop", { _ in }),
            ("underline", { $0.placeName.inkMark = .underline })
        ]
        if scene.appearance == .dark {
            variants.append(("loop-trail-ink", { $0.placeName.inkColor = RecapStyle.trailOnDark }))
        }
        let outDir = RecapReviewScene.outputDirectory()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for variant in variants {
            let image = try await scene.restyled(variant.change).frame(at: time)
            let url = outDir.appendingPathComponent("souvenir-\(fixture)-\(scene.appearance.rawValue)-\(variant.label).png")
            let destination = try XCTUnwrap(
                CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
            )
            CGImageDestinationAddImage(destination, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination), "PNG write failed")
            print(String(
                format: "KAMOME_INK_STILL %@ — t=%.2fs of a %.2fs film", url.path, time, scene.timeline.durationS
            ))
        }
    }
}
