@testable import Kamome
import KamomeExportEngine
import XCTest
#if canImport(MapLibre)
import UIKit
#endif

/// Manual review harness for §3 Modern Minimal — **not** a CI test. It drives the
/// real MapLibre snapshotter (Metal) over the committed Perth fixture tiles and
/// writes PNG stills you open by eye. Env-gated (like `RecapMatchingE2ETests`) so
/// it never runs in CI: MapLibre rendering is non-deterministic Metal and must not
/// gate golden frames (vector-tile-pipeline §8). It asserts only that a real,
/// non-blank frame came back — the *look* is Chiu's call, not a pixel golden.
///
/// Run (simulator):
///   KAMOME_RENDER_STILLS=1 xcodebuild -scheme Kamome test \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///     -only-testing:KamomeTests/ModernMinimalRenderTests
/// The console prints the output directory; open the PNGs there. Override the
/// location with KAMOME_RENDER_OUT=/some/dir.
final class ModernMinimalRenderTests: XCTestCase {
    /// Camera positions inside the committed Margaret River fixture crop
    /// (bbox 114.96,-34.00 → 115.16,-33.78). `span1500` matches
    /// export.camera_span_m; the wider frames show the coastline.
    private struct Shot {
        let name: String
        let lat: Double
        let lon: Double
        let spanM: Double
    }

    private let shots: [Shot] = [
        Shot(name: "town-close", lat: -33.955, lon: 115.075, spanM: 1500),
        Shot(name: "town-mid", lat: -33.955, lon: 115.075, spanM: 4000),
        Shot(name: "coast-wide", lat: -33.900, lon: 115.040, spanM: 12000)
    ]

    private func fixtureTilesURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/AppTests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent("Fixtures/tiles/perth-2026-07-19.pmtiles")
    }

    #if canImport(MapLibre)
    func testRenderStillsForReview() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_RENDER_STILLS"] == "1",
            "Manual review harness — set KAMOME_RENDER_STILLS=1 to render Modern Minimal stills."
        )

        let tiles = fixtureTilesURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tiles.path), "fixture tiles missing at \(tiles.path)")

        let outDir: URL
        if let override = ProcessInfo.processInfo.environment["KAMOME_RENDER_OUT"] {
            outDir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            outDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("kamome-modern-minimal-stills", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // Both themes side by side: the §2 functional base and the §3 draft.
        for theme in ["functional-base", "modern-minimal"] {
            let styleURL = try RecapMapStyle.resolvedStyleURL(styleResource: theme, tilesURL: tiles)
            let provider = MapLibreSnapshotProvider(styleURL: styleURL)
            for shot in shots {
                let snapshot = try await provider.snapshot(
                    centerLat: shot.lat, centerLon: shot.lon, spanM: shot.spanM,
                    widthPx: 1080, heightPx: 1920
                )
                let image = snapshot.image
                XCTAssertEqual(image.width, 1080)
                XCTAssertEqual(image.height, 1920)
                XCTAssertFalse(
                    try isBlank(image),
                    "\(theme)/\(shot.name) rendered a single flat colour — tiles likely did not load"
                )

                let file = outDir.appendingPathComponent("\(theme)-\(shot.name).png")
                let png = try XCTUnwrap(UIImage(cgImage: image).pngData(), "PNG encode failed")
                try png.write(to: file)
            }
        }
        // Printed so the reviewer can find and open the stills.
        print("KAMOME MODERN-MINIMAL STILLS → \(outDir.path)")
    }

    /// A rendered map is never one uniform colour; a blank frame means the tiles
    /// didn't load (wrong pmtiles:// path/scheme) even though the API succeeded.
    private func isBlank(_ image: CGImage) throws -> Bool {
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        let bytesPerRow = image.bytesPerRow
        let first = (bytes[0], bytes[1], bytes[2])
        // Sample a coarse grid; if every sample equals the first pixel, it's flat.
        for row in stride(from: 0, to: image.height, by: 64) {
            for col in stride(from: 0, to: image.width, by: 64) {
                let offset = row * bytesPerRow + col * 4
                if (bytes[offset], bytes[offset + 1], bytes[offset + 2]) != first {
                    return false
                }
            }
        }
        return true
    }
    #endif
}
