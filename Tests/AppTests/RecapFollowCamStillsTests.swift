import CoreGraphics
import ImageIO
@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import UniformTypeIdentifiers
import XCTest
#if canImport(MapLibre)
import UIKit
#endif

/// Manual review harness for the TravelBoast-class follow-cam redesign — **not**
/// a CI test. It composites the moving subject (the anime car sprite, or the
/// ported gull) over the **real** MapLibre modern-minimal tiles at heading-up
/// follow-cam frames, so Chiu can judge the actual look — car over the dark
/// souvenir map, map rotating under an upright hero car. Env-gated (Metal, like
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
    private let route: [CameraPath.Point] = (0...16).map { index in
        let step = Double(index)
        return CameraPath.Point(lat: -33.965 + step * 0.0013, lon: 115.072 + 0.006 * sin(step / 3))
    }

    private func followCamConfig(headingUp: Bool) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: 12, fps: 30, stopHoldS: 1.5, maxHoldFraction: 0.6,
            gifFps: 12, gifWidthPx: 480, frameWidthPx: width, frameHeightPx: height,
            cameraSpanM: 1200, wideSpanPadding: 1.15, zoomTransitionS: 0.8, followHeadingUp: headingUp,
            deckPhotoHoldS: 0.8, deckZoomS: 0.5, deckSpanM: 600, deckLabelLeadS: 0.6,
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

        // Heading-up: the anime car rides upright while the map rotates under it.
        let car = try carSprite()
        try await renderPass(
            provider: provider, config: followCamConfig(headingUp: true),
            style: carStyle(sprite: car), prefix: "car-headingup", to: outDir
        )
        // North-up contrast: same car, map not rotated (shows why heading-up wins).
        try await renderPass(
            provider: provider, config: followCamConfig(headingUp: false),
            style: carStyle(sprite: car), prefix: "car-northup", to: outDir
        )
        // The ported gull, heading-up.
        try await renderPass(
            provider: provider, config: followCamConfig(headingUp: true),
            style: gullStyle(), prefix: "gull-headingup", to: outDir
        )
        print("KAMOME FOLLOW-CAM STILLS → \(outDir.path)")
    }

    /// Renders four body-time frames through the given style over live tiles.
    private func renderPass(
        provider: MapLibreSnapshotProvider,
        config: TrackingConfig.Export,
        style: RecapStyle,
        prefix: String,
        to outDir: URL
    ) async throws {
        let path = try XCTUnwrap(CameraPath(route: route, stops: [], config: config))
        let compositor = RecapFrameCompositor(
            path: path, events: [], stopCards: [], widthPx: width, heightPx: height, style: style
        )
        for time in [3.0, 5.0, 7.0, 9.0] {
            let frame = path.cameraFrame(atTime: time)
            let snapshot = try await provider.snapshot(
                CameraFrame(centerLat: frame.centerLat, centerLon: frame.centerLon, spanM: frame.spanM, bearing: frame.bearing),
                map: MapState(), widthPx: width, heightPx: height
            )
            let image = try compositor.render(atTime: time, background: RecapBackground(current: snapshot))
            try writePNG(image, to: outDir, name: "\(prefix)-\(Int(time))s")
        }
    }

    // MARK: - Styles

    private func carStyle(sprite: CGImage) -> RecapStyle {
        var style = glowRouteStyle()
        style.markerImage = sprite
        style.markerImageHeightPx = 380
        return style
    }

    private func gullStyle() -> RecapStyle {
        var style = glowRouteStyle()
        style.vehicleMarker = .seagull
        style.markerColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        style.vehicleMarkerLengthPx = 150
        return style
    }

    /// A brighter route so it reads as a glowing trail on the dark map.
    private func glowRouteStyle() -> RecapStyle {
        var style = RecapStyle()
        style.routeColor = CGColor(srgbRed: 0.35, green: 0.85, blue: 0.95, alpha: 1)
        style.routeWidthPx = 18
        return style
    }

    // MARK: - Helpers

    private func carSprite() throws -> CGImage {
        let url = repoRootURL().appendingPathComponent("Docs/demos/car.webp")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), "car.webp unreadable at \(url.path)")
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), "car.webp decode failed")
    }

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
