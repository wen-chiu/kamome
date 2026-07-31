import CoreGraphics
import CoreText
import ImageIO
@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import UniformTypeIdentifiers
import XCTest
#if canImport(MapLibre)
import UIKit
#endif

/// Manual review harness for the follow-cam redesign — **not** a CI test. It
/// composites the moving subject over the **real** MapLibre modern-minimal tiles
/// so Chiu can judge the actual look: the heading sweep (a fixed north-up map
/// with the car switching between its eight drawings), the follow-cam, and the
/// two-beat stop scene (floating name → photo reveal). Env-gated (Metal, like
/// `ModernMinimalRenderTests`) so it never runs in CI.
///
/// Run (simulator):
///   KAMOME_FOLLOWCAM_STILLS=1 xcodebuild -scheme Kamome test \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///     -only-testing:KamomeTests/RecapFollowCamStillsTests
/// Output dir is printed; override with KAMOME_RENDER_OUT.
final class RecapFollowCamStillsTests: XCTestCase {
    private let width = 1080
    private let height = 1920

    /// A curved route inside the committed Margaret River fixture crop so the
    /// heading swings — the map visibly rotates under the car between frames.
    private let route: [RecapCoordinate] = (0...16).map { index in
        let step = Double(index)
        return RecapCoordinate(lat: -33.965 + step * 0.0013, lon: 115.072 + 0.006 * sin(step / 3))
    }

    private func followCamConfig(headingUp: Bool) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: 12, fps: 30, stopHoldS: 1.5, maxHoldFraction: 0.6,
            gifFps: 12, gifWidthPx: 480, frameWidthPx: width, frameHeightPx: height,
            cameraSpanM: 1200, wideSpanPadding: 1.15, zoomTransitionS: 0.8, actSplitKm: 25, followHeadingUp: headingUp,
            deckPhotoHoldS: 0.8, deckZoomS: 0.5, deckLabelLeadS: 0.6, subjectParkS: 0.4,
            openingCountryS: 3.0, openingRegionalS: 3.5, openingRouteS: 0.4,
            countryViewPadding: 2.2, firstStopDwellScale: 0.55,
            openingCollapseZoomRatio: 1.25, openingCollapseDriftFraction: 0.15,
            stopDwellMinS: 6, stopDwellMaxS: 25,
            totalDurationMinS: 60, totalDurationMaxS: 90,
            keyframeIntervalFrames: 15, titleCardS: 1, endCardS: 1, videoBitrateMbps: 5
        )
    }

    #if canImport(MapLibre)
    func testRenderFollowCamStills() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_FOLLOWCAM_STILLS"] == "1",
            "Manual review harness — set KAMOME_FOLLOWCAM_STILLS=1 to render follow-cam stills."
        )
        let tiles = fixtureTilesURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tiles.path), "fixture tiles missing at \(tiles.path)")
        let styleURL = try RecapMapStyle.resolvedStyleURL(styleResource: "modern-minimal", tilesURL: tiles)
        let provider = MapLibreSnapshotProvider(styleURL: styleURL)
        let outDir = outputDirectory()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // The heading sweep: one frame per travel direction over a map that never
        // turns, the car switching between its eight drawings (Chiu 2026-07-25).
        try await renderHeadingSweep(provider: provider, to: outDir)
        // The shipping follow-cam: north-up map, 8-way car sprite.
        try await renderPass(
            provider: provider, config: followCamConfig(headingUp: false),
            style: carStyle(), prefix: "car-northup", to: outDir
        )
        // The Layer-3 sign-off shot: the two-beat stop scene (pin/name lead →
        // photo reveal) as the camera dollies in over the dark souvenir map.
        try await renderStopScene(provider: provider, to: outDir)
        print("KAMOME FOLLOW-CAM STILLS → \(outDir.path)")
    }

    /// The two-beat stop scene over live tiles: the pin lands with its name
    /// floating clear above the car, then the photo card opens as the camera
    /// dollies in — sampled at the lead, the card's first frame, and full reveal.
    private func renderStopScene(provider: MapLibreSnapshotProvider, to outDir: URL) async throws {
        let config = followCamConfig(headingUp: false)
        let deck = RecapDeck(photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS, labelLeadS: config.deckLabelLeadS)
        let photos = try (0..<4).map { try photoTile(index: $0) }
        let refs = (0..<photos.count).map { PhotoRef.asset("p\($0)") }
        let images = Dictionary(uniqueKeysWithValues: zip((0..<photos.count).map { "p\($0)" }, photos))
        let stop = RecapTrip.Stop(
            coordinate: route[8], name: "小樽運河", dayLabel: "Day 3", detail: "步行 12 分鐘",
            photos: refs, dwellS: deck.dwellS(photoCount: refs.count)
        )
        let trip = RecapTrip(
            route: route, stops: [stop], title: "小樽", subtitle: "Day 3",
            statsLines: ["120 km · 1 停留"], callToAction: "Get this route", shareURL: "kamome://route/otaru"
        )
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config))
        let style = carStyle()
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(style: style),
            overlay: RecapOverlayRenderer(style: style, resolver: MapResolver(images: images)),
            widthPx: width, heightPx: height
        )
        guard let beats = stopSceneTimes(timeline) else { return }
        for (name, time) in [("stop-label-lead", beats.lead), ("stop-deck-open", beats.grow), ("stop-deck-full", beats.peak)] {
            let frame = timeline.cameraFrame(atTime: time)
            let snapshot = try await provider.snapshot(
                CameraFrame(centerLat: frame.centerLat, centerLon: frame.centerLon, spanM: frame.spanM, bearing: frame.bearing),
                map: MapState(), widthPx: width, heightPx: height
            )
            let image = try compositor.render(atTime: time, background: RecapBackground(current: snapshot))
            try writePNG(image, to: outDir, name: name)
        }
    }

    /// The three instants the stop scene is sampled at for review.
    private struct StopBeats {
        let lead: Double
        let grow: Double
        let peak: Double
    }

    /// Locates the stop scene's beats: the label lead (name up, no card yet), the
    /// card at its opening size, and its fullest reveal. The opening beat is the
    /// first *fully opaque* frame — the card's first frames are still fading in,
    /// so sampling those would just re-shoot the lead.
    private func stopSceneTimes(_ timeline: LinearTimeline) -> StopBeats? {
        var leadTime: Double?
        var deckSamples: [RecapPhotoDeck] = []
        var deckTimes: [Double] = []
        var time = 0.0
        while time <= timeline.durationS {
            let contents = timeline.overlayContents(atTime: time)
            let hasLabel = contents.contains { if case .stopLabel = $0 { return true }; return false }
            let deck = contents.compactMap { content -> RecapPhotoDeck? in
                if case let .photoDeck(deck) = content { return deck }
                return nil
            }.first
            if hasLabel, deck == nil, leadTime == nil { leadTime = time }
            if let deck {
                deckSamples.append(deck)
                deckTimes.append(time)
            }
            time += 1.0 / 30
        }
        let opaque = zip(deckTimes, deckSamples).filter { $0.1.opacity > 0.95 }
        guard let lead = leadTime, let grow = opaque.first?.0,
              let peak = opaque.max(by: { $0.1.reveal < $1.1.reveal })?.0 else { return nil }
        return StopBeats(lead: lead, grow: grow, peak: peak)
    }

    /// A stand-in "photo": a diagonal gradient with a big index, so the deck's
    /// framing and rotation read clearly in the still.
    private func photoTile(index: Int) throws -> CGImage {
        let side = 900
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let palettes: [(CGColor, CGColor)] = [
            (CGColor(srgbRed: 0.20, green: 0.45, blue: 0.70, alpha: 1),
             CGColor(srgbRed: 0.10, green: 0.22, blue: 0.35, alpha: 1)),
            (CGColor(srgbRed: 0.75, green: 0.45, blue: 0.30, alpha: 1),
             CGColor(srgbRed: 0.38, green: 0.22, blue: 0.15, alpha: 1)),
            (CGColor(srgbRed: 0.35, green: 0.60, blue: 0.40, alpha: 1),
             CGColor(srgbRed: 0.18, green: 0.30, blue: 0.20, alpha: 1)),
            (CGColor(srgbRed: 0.55, green: 0.35, blue: 0.55, alpha: 1),
             CGColor(srgbRed: 0.28, green: 0.18, blue: 0.28, alpha: 1))
        ]
        let (top, bottom) = palettes[index % palettes.count]
        let gradient = try XCTUnwrap(CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]))
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 320, nil)
        let textColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85)
        let attrs = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: textColor] as CFDictionary
        let attributed = CFAttributedStringCreate(kCFAllocatorDefault, "\(index + 1)" as CFString, attrs)
        let line = CTLineCreateWithAttributedString(attributed!)
        let bounds = CTLineGetImageBounds(line, context)
        context.textPosition = CGPoint(x: (CGFloat(side) - bounds.width) / 2, y: (CGFloat(side) - bounds.height) / 2)
        CTLineDraw(line, context)
        return try XCTUnwrap(context.makeImage())
    }

    /// Renders four body-time frames through the given style over live tiles.
    private func renderPass(
        provider: MapLibreSnapshotProvider,
        config: TrackingConfig.Export,
        style: RecapStyle,
        prefix: String,
        to outDir: URL
    ) async throws {
        let trip = RecapTrip(
            route: route, stops: [], title: "Follow-cam", subtitle: "Stills",
            statsLines: [], callToAction: "", shareURL: "kamome://route/followcam"
        )
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config))
        // The pass's own orientation decides the subject: heading-up gets the
        // raster hero car, north-up the vector fallback.
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(style: style),
            overlay: RecapOverlayRenderer(style: style, resolver: FollowCamNoPhotoResolver()),
            widthPx: width, heightPx: height
        )
        for time in [3.0, 5.0, 7.0, 9.0] {
            let frame = timeline.cameraFrame(atTime: time)
            let snapshot = try await provider.snapshot(
                CameraFrame(centerLat: frame.centerLat, centerLon: frame.centerLon, spanM: frame.spanM, bearing: frame.bearing),
                map: MapState(), widthPx: width, heightPx: height
            )
            let image = try compositor.render(atTime: time, background: RecapBackground(current: snapshot))
            try writePNG(image, to: outDir, name: "\(prefix)-\(Int(time))s")
        }
    }

    // MARK: - Styles

    /// The shipping raster hero car over the glowing trail.
    private func carStyle() -> RecapStyle {
        glowRouteStyle()
    }

    /// A brighter route so it reads as a glowing trail on the dark map.
    private func glowRouteStyle() -> RecapStyle {
        var style = RecapStyle()
        style.routeColor = CGColor(srgbRed: 0.35, green: 0.85, blue: 0.95, alpha: 1)
        style.routeWidthPx = 18
        return style
    }

    // MARK: - Helpers

    private func fixtureTilesURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/AppTests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent("Fixtures/tiles/perth-2026-07-19.pmtiles")
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/AppTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    private func outputDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["KAMOME_RENDER_OUT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("kamome-followcam-stills", isDirectory: true)
    }

    private func writePNG(_ image: CGImage, to dir: URL, name: String) throws {
        let url = dir.appendingPathComponent("\(name).png")
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "PNG write failed for \(name)")
    }
    #endif
}

#if canImport(MapLibre)
/// The heading-sweep pass, split out to keep the harness type small.
private extension RecapFollowCamStillsTests {
    /// A route whose travel heading turns steadily from −90° to 450°: each step
    /// advances a fixed distance along a slightly rotated heading, curling into a
    /// loop that passes through all eight sprite directions.
    ///
    /// It deliberately overshoots a full turn at both ends: sampling skips the
    /// title and end windows (where the camera is still easing between the wide
    /// shot and the close follow), so 0° and 315° have to occur comfortably
    /// *inside* the body of the film rather than at the route's first and last
    /// vertex.
    private var sweepRoute: [RecapCoordinate] {
        var coords = [RecapCoordinate(lat: -33.9695, lon: 115.0715)]
        let steps = 140, stepM = 20.0
        for index in 0..<steps {
            let heading = (-90.0 + 540.0 * Double(index) / Double(steps)) * .pi / 180
            let previous = coords[coords.count - 1]
            coords.append(RecapCoordinate(
                lat: previous.lat + stepM * cos(heading) / 111_320,
                lon: previous.lon + stepM * sin(heading) / (111_320 * cos(previous.lat * .pi / 180))
            ))
        }
        return coords
    }

    /// The heading sweep, rendered through the **real pipeline** — one full frame
    /// per heading, trail included.
    ///
    /// The map is fixed north-up, so what changes between these frames is the
    /// *car*: the route turns through each heading and the renderer swaps to the
    /// matching one of eight drawings. The nose must line up with the trail every
    /// time, and the map must be identically oriented in all five.
    private func renderHeadingSweep(provider: MapLibreSnapshotProvider, to outDir: URL) async throws {
        let config = followCamConfig(headingUp: false)
        let trip = RecapTrip(
            route: sweepRoute, stops: [], title: "Heading sweep", subtitle: "",
            statsLines: [], callToAction: "", shareURL: "kamome://route/sweep"
        )
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config))
        let style = carStyle()
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(style: style),
            overlay: RecapOverlayRenderer(style: style, resolver: FollowCamNoPhotoResolver()),
            widthPx: width, heightPx: height
        )

        for target in SpriteDirection.allCases.map(\.degrees) {
            guard let time = timeOfHeading(target, in: timeline, config: config) else {
                XCTFail("the sweep route never travels at \(Int(target))°")
                continue
            }
            let actual = timeline.subjectState(atTime: time).heading
            let frame = timeline.cameraFrame(atTime: time)
            let snapshot = try await provider.snapshot(
                CameraFrame(
                    centerLat: frame.centerLat, centerLon: frame.centerLon,
                    spanM: frame.spanM, bearing: frame.bearing
                ),
                map: MapState(), widthPx: width, heightPx: height
            )
            let image = try compositor.render(atTime: time, background: RecapBackground(current: snapshot))
            print(String(format: "  heading %3d° → t=%.2fs actual=%.1f° mapBearing=%.1f° sprite=%@",
                         Int(target), time, actual, frame.bearing,
                         SpriteDirection.nearest(toBearing: actual - frame.bearing).rawValue))
            try writePNG(image, to: outDir, name: String(format: "car-heading-%03d", Int(target)))
        }
    }

    /// The body-shot instant whose travel heading is closest to `target`. Skips
    /// the title/end windows, where the camera is still easing between the wide
    /// establishing shot and the close follow and the bearing is only part-way
    /// applied.
    private func timeOfHeading(
        _ target: Double, in timeline: LinearTimeline, config: TrackingConfig.Export
    ) -> Double? {
        var best: (time: Double, error: Double)?
        var time = config.titleCardS + config.zoomTransitionS
        let end = timeline.durationS - config.endCardS - config.zoomTransitionS
        while time <= end {
            let heading = timeline.subjectState(atTime: time).heading
            var error = abs(heading - target).truncatingRemainder(dividingBy: 360)
            if error > 180 { error = 360 - error }
            if best == nil || error < best!.error { best = (time, error) }
            time += 1.0 / 30
        }
        guard let best, best.error < 8 else { return nil }
        return best.time
    }
}
#endif

/// The route-only follow-cam passes have no deck photos to resolve.
private struct FollowCamNoPhotoResolver: RecapPhotoResolving {
    func image(for ref: PhotoRef, targetPx: Int) -> CGImage? { nil }
}

/// Resolves the stop-scene stand-in photos from an in-memory id→bitmap map.
private struct MapResolver: RecapPhotoResolving {
    let images: [String: CGImage]
    func image(for ref: PhotoRef, targetPx: Int) -> CGImage? {
        if case let .asset(id) = ref { return images[id] }
        return nil
    }
}
