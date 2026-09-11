import CoreGraphics
import CoreText
import ImageIO
@testable import Kamome
import KamomeExportEngine
import UniformTypeIdentifiers
import XCTest

// `MapLibreSnapshotProvider` is itself behind this guard, and this whole harness
// exists to render it — the same shape `RecapDemoFilmSubstrate` already uses.
#if canImport(MapLibre)

/// **The OpenFreeMap + MapLibre export-substrate evaluation** (ADR 2026-09-09).
/// Manual review harness, env-gated, never CI.
///
/// It answers one question and refuses to answer any other: *does the film look
/// better on an OpenFreeMap style than on the Apple Maps base that ships today?*
/// That is Chiu's judgement, so this returns **pictures and one number** — it
/// decides nothing, changes no build, and touches no shipping code path.
///
/// **Why one test rather than four runs of `RecapStopStillTests`.** A comparison
/// is worth looking at only if the camera, the timeline, the overlay and the
/// photo deck are provably identical across the frames, and the only way to
/// guarantee that is to build the scene once and vary nothing but the substrate
/// argument. Four separate `xcodebuild` runs would each re-import the trip and
/// could differ in any of the above without saying so.
///
/// **Two scenes, not one**, because the palette drawn over the base has to match
/// the base (`MapRendererCapabilities.fixedAppearance`, ADR 2026-08-27):
/// Positron and Liberty are light grounds, Fiord is a dark one. The timeline is
/// built from the trip and config alone — never from the style — so both scenes
/// share one camera, which is what makes the light and dark frames comparable.
///
///     TEST_RUNNER_KAMOME_SUBSTRATE_EVAL=miyakojima \
///     TEST_RUNNER_KAMOME_ROUTING_BASE_URL=https://kamome-routing.kamome-site.workers.dev \
///     TEST_RUNNER_KAMOME_STOP_PHOTOS=/path/to/jpegs \
///     TEST_RUNNER_KAMOME_RENDER_OUT=$HOME/Kamome-films/openfreemap-eval \
///     xcodebuild -scheme Kamome test -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///       -only-testing:KamomeTests/RecapSubstrateEvalTests
final class RecapSubstrateEvalTests: XCTestCase {
    /// One row of the comparison: what was drawn, and what it cost.
    private struct Render {
        let label: String
        let appearance: RecapAppearance
        let image: CGImage
        let camera: CameraFrame
        /// Every pass's wall time, in order. The first is the cold-cache one.
        let snapshotS: [Double]
        /// The attribution this frame's data obliges, or nil for the Apple
        /// baseline. **Not a constant on the strip.** The first run of this
        /// harness stamped `OpenFreeMap © OpenMapTiles Data from OpenStreetMap`
        /// onto the Apple frames too, which is a false provenance claim on a
        /// picture — the exact thing `CLAUDE.md` rule 5 is about — and it would
        /// have been read as one the moment the four frames were put side by side.
        let attribution: String?
    }

    /// How many times each substrate renders the frame. Two, so the cold number
    /// and the warm number both exist and neither has to be guessed at.
    private static let passes = 2

    func testRenderSubstrateComparison() async throws {
        let fixture = HarnessEnv.value("KAMOME_SUBSTRATE_EVAL") ?? ""
        try XCTSkipUnless(
            !fixture.isEmpty,
            "Manual review harness — set KAMOME_SUBSTRATE_EVAL to a fixture name (e.g. miyakojima)."
        )
        // The eval drives the substrates itself, so it must not also be steered
        // by the switch it added. Refusing beats quietly rendering four copies of
        // one style and labelling them as four different ones.
        try XCTSkipIf(
            HarnessEnv.value("KAMOME_MAP_SUBSTRATE") != nil,
            "KAMOME_MAP_SUBSTRATE steers a single-substrate render; this harness renders all of them."
        )

        let light = try await RecapReviewScene.make(fixture: fixture, appearance: .light)
        let time = try XCTUnwrap(
            HarnessEnv.value("KAMOME_SUBSTRATE_EVAL_T").flatMap(Double.init)
                ?? light.travellingTime(),
            "the film never shows a moving subject — pin one with KAMOME_SUBSTRATE_EVAL_T"
        )
        var renders = try await self.renders(on: light, at: time, styles: [.openFreeMapPositron, .openFreeMapLiberty])

        // The dark half. Rebuilt rather than restyled: the compositor bakes the
        // palette in at construction, and reaching into it would be a second way
        // to build a scene.
        let dark = try await RecapReviewScene.make(fixture: fixture, appearance: .dark)
        renders += try await self.renders(on: dark, at: time, styles: [.openFreeMapFiord])

        let outDir = RecapReviewScene.outputDirectory()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for render in renders {
            let url = outDir.appendingPathComponent("substrate-\(fixture)-\(render.label).png")
            try write(annotate(render, fixture: fixture, time: time), to: url)
            print("KAMOME_SUBSTRATE_EVAL \(url.path)")
        }
        report(renders, fixture: fixture, time: time)
    }

    /// The baseline plus each requested style, all on `scene`'s single camera.
    ///
    /// **Apple Maps is rendered in every group, not once.** It is the baseline the
    /// whole round exists to beat, and a light baseline cannot be compared with a
    /// dark Fiord frame — so each appearance gets its own.
    private func renders(
        on scene: RecapReviewScene, at time: Double, styles: [ReviewSubstrate.Substrate]
    ) async throws -> [Render] {
        var result: [Render] = [
            try await render(
                on: scene, at: time, label: "apple-\(scene.appearance.rawValue)",
                using: scene.provider, attribution: nil
            )
        ]
        for style in styles {
            // The scene's appearance is the one this style declares, or the scene
            // would be drawing the wrong palette over it.
            XCTAssertEqual(
                style.appearance, scene.appearance,
                "\(style.rawValue) is a \(style.appearance.rawValue) ground and must not be "
                    + "drawn under the \(scene.appearance.rawValue) palette"
            )
            result.append(try await render(
                on: scene, at: time, label: "openfreemap-\(style.rawValue)",
                using: MapLibreSnapshotProvider(styleURL: style.styleURL, appearance: style.appearance),
                attribution: ReviewSubstrate.Substrate.attribution
            ))
        }
        return result
    }

    private func render(
        on scene: RecapReviewScene, at time: Double, label: String,
        using renderer: MapRenderer, attribution: String?
    ) async throws -> Render {
        var timings: [Double] = []
        var last: RenderedFrame?
        for _ in 0..<Self.passes {
            let pass = try await scene.frame(at: time, using: renderer)
            timings.append(pass.snapshotS)
            last = pass
        }
        let final = try XCTUnwrap(last)
        return Render(
            label: label, appearance: scene.appearance, image: final.image,
            camera: final.camera, snapshotS: timings, attribution: attribution
        )
    }

    // MARK: - The console report

    /// **The number, and what kind of number it is.** Seconds per snapshot is
    /// meaningless without its cache state: the only prior MapLibre figure
    /// (0.84 s) was local `.pmtiles` and this one is network tiles, so latency
    /// dominates it. Both passes are printed rather than averaged.
    ///
    /// ⚠️ **All three styles read the same tile source**
    /// (`tiles.openfreemap.org/planet`), so only the first OpenFreeMap style in a
    /// run pays a genuinely cold *tile* fetch — the later two still pay a cold
    /// style, glyph and sprite fetch. Stated here because averaging them would
    /// have hidden it.
    private func report(_ renders: [Render], fixture: String, time: Double) {
        print("KAMOME_SUBSTRATE_EVAL ── \(fixture) @ t=\(String(format: "%.2f", time))s ──")
        for render in renders {
            let passes = render.snapshotS
                .map { String(format: "%.2f", $0) }.joined(separator: " / ")
            print(String(
                format: "KAMOME_SUBSTRATE_EVAL %-24@ %@ · z%.2f · span %.1f km · s/snapshot %@ (cold / warm)",
                render.label as NSString, render.appearance.rawValue,
                zoomLevel(render.camera), render.camera.spanM / 1000, passes
            ))
        }
        print("KAMOME_SUBSTRATE_EVAL attribution on the OpenFreeMap frames only: "
            + ReviewSubstrate.Substrate.attribution
            + " — MLNMapSnapshotter also burns its own copy in (showsAttribution defaults true)")
    }

    /// The web-Mercator zoom this frame corresponds to — the same function
    /// `MapLibreSnapshotProvider` uses to drive the snapshotter. Reported for the
    /// Apple frames too, where it is an *equivalent* zoom rather than one MapKit
    /// was given, so the four captions carry one comparable number.
    private func zoomLevel(_ camera: CameraFrame) -> Double {
        MapLibreSnapshotProvider.zoomLevel(
            spanM: camera.spanM, widthPx: 1080, latitude: camera.centerLat
        )
    }

    // MARK: - Annotation

    /// The film frame with a caption strip **added below it**, never drawn over
    /// it. A screenshot with no caption is worthless three days later, and a
    /// caption painted into the film would be judged as part of the film.
    private func annotate(_ render: Render, fixture: String, time: Double) throws -> CGImage {
        let width = render.image.width
        let strip = 132
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: render.image.height + strip,
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw RecapReviewScene.SetupError.noPhotoTile }
        context.setFillColor(CGColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: strip))
        context.draw(
            render.image,
            in: CGRect(x: 0, y: strip, width: width, height: render.image.height)
        )
        let cold = render.snapshotS.first ?? 0
        let warm = render.snapshotS.last ?? 0
        draw([
            "\(render.label)   ·   \(fixture)   ·   t=\(String(format: "%.2f", time))s",
            String(
                format: "z %.2f · span %.1f km · %@ · %.2f s cold / %.2f s warm",
                zoomLevel(render.camera), render.camera.spanM / 1000,
                render.appearance.rawValue, cold, warm
            )
        ] + (render.attribution.map { [$0] } ?? []), in: context, width: width, stripHeight: strip)
        guard let image = context.makeImage() else { throw RecapReviewScene.SetupError.noPhotoTile }
        return image
    }

    /// **Every caption line is measured and shrunk to fit before it is drawn.**
    /// The first run of this harness clipped the numbers line at the frame edge —
    /// which is the one failure an annotation cannot have, since a caption that
    /// silently loses its right-hand end is worse than no caption at all.
    private func draw(_ lines: [String], in context: CGContext, width: Int, stripHeight: Int) {
        let margin: CGFloat = 28
        let available = CGFloat(width) - margin * 2
        for (index, line) in lines.enumerated() {
            var size: CGFloat = 26
            var typeset = self.line(line, size: size)
            while CTLineGetTypographicBounds(typeset, nil, nil, nil) > Double(available), size > 10 {
                size -= 1
                typeset = self.line(line, size: size)
            }
            context.textPosition = CGPoint(x: margin, y: CGFloat(stripHeight - 42 - index * 36))
            CTLineDraw(typeset, context)
        }
    }

    private func line(_ text: String, size: CGFloat) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            .font: CTFontCreateWithName("Menlo-Regular" as CFString, size, nil),
            .foregroundColor: CGColor(srgbRed: 0.92, green: 0.93, blue: 0.94, alpha: 1)
        ]))
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "PNG write failed")
    }
}
#endif
