import CoreGraphics
import CoreLocation
import ImageIO
@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import KamomeTrackingEngine
import MapKit
import UniformTypeIdentifiers
import XCTest

/// **Where the long-haul boundary actually is, and whose limit it is** — the
/// second half of the 2026-09-01 type-2 probe (`LongHaulFrameProbeTests` holds
/// the four-pair half).
///
/// Split from it only because one file cannot hold both under the 400-line
/// limit; they are one investigation and share its env gate:
///
///   TEST_RUNNER_KAMOME_LONGHAUL_PROBE=1 \
///   TEST_RUNNER_KAMOME_RENDER_OUT=/path/to/out \
///   xcodebuild -scheme Kamome test -destination '…' \
///     -only-testing:KamomeTests/LongHaulCeilingProbeTests
final class LongHaulCeilingProbeTests: XCTestCase {
    private func requireProbe() throws {
        try XCTSkipUnless(
            HarnessEnv.value("KAMOME_LONGHAUL_PROBE") == "1",
            "Live long-haul MapKit probe — set TEST_RUNNER_KAMOME_LONGHAUL_PROBE=1."
        )
    }

    private func exportConfig() throws -> TrackingConfig.Export {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "TrackingConfig", withExtension: "json"),
            "TrackingConfig.json missing from app bundle"
        )
        return try TrackingConfigLoader.load(contentsOf: url).export
    }

    /// Share of pixels in the most common of 256 luminance buckets, and how many
    /// buckets hold at least 0.1% — enough to tell a map from a flat field.
    private struct Spread {
        let mean: Double
        let sd: Double
        /// How many of 256 luminance buckets hold at least 0.1% of the picture.
        let buckets: Int
    }

    private func spread(of image: CGImage) throws -> Spread {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var histogram = [Int](repeating: 0, count: 256)
        for value in pixels { histogram[Int(value)] += 1 }
        let total = Double(pixels.count)
        let mean = pixels.reduce(0.0) { $0 + Double($1) } / total
        let variance = pixels.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / total
        let floorCount = Int(total * 0.001)
        return Spread(
            mean: mean, sd: sqrt(variance), buckets: histogram.filter { $0 >= floorCount }.count
        )
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "PNG write failed")
    }

    /// Three attempts, and the failures kept. A single failure cannot tell a
    /// scale MapKit refuses from a tile server having a bad minute.
    private static func snapshot(
        at center: CLLocationCoordinate2D, spanKm: Double, appearance: RecapAppearance,
        widthPx: Int, heightPx: Int
    ) async -> (snapshot: MapSnapshot?, failures: [String]) {
        let provider = MapKitSnapshotProvider(appearance: appearance)
        var snapshot: MapSnapshot?
        var failures: [String] = []
        for _ in 1...3 where snapshot == nil {
            do {
                snapshot = try await provider.snapshot(
                    CameraFrame(
                        centerLat: center.latitude, centerLon: center.longitude,
                        spanM: spanKm * 1000, bearing: 0
                    ),
                    map: MapState(), widthPx: widthPx, heightPx: heightPx
                )
            } catch {
                failures.append("\(error)")
            }
        }
        return (snapshot, failures)
    }

    /// What MapKit *actually* rendered, read back off its own projection rather
    /// than assumed from what was asked for: two known longitudes 90 degrees
    /// apart give the frame's real width. This is the measurement that found the
    /// zoom floor — three different requests came back the same width.
    private static func renderedLongitudeDeg(
        _ snapshot: MapSnapshot, center: CLLocationCoordinate2D, widthPx: Int
    ) -> Double {
        let west = snapshot.point(lat: center.latitude, lon: center.longitude - 45)
        let east = snapshot.point(lat: center.latitude, lon: center.longitude + 45)
        return east.x > west.x ? 90 * Double(widthPx) / (east.x - west.x) : .infinity
    }

    /// One sweep row: what came back, and where the two cities landed in it.
    private func report(
        _ snapshot: MapSnapshot, label: String, spanKm: Double,
        center: CLLocationCoordinate2D, frame: (widthPx: Int, heightPx: Int), failures: [String]
    ) throws {
        let widthPx = frame.widthPx
        let heightPx = frame.heightPx
        let look = try spread(of: snapshot.image)
        let taipei = snapshot.point(lat: 25.0330, lon: 121.5654)
        let paris = snapshot.point(lat: 48.8566, lon: 2.3522)
        let inside = { (point: CGPoint) in
            point.x >= 0 && point.x <= Double(widthPx) && point.y >= 0 && point.y <= Double(heightPx)
        }
        print(String(
            format: "KAMOME_LONGHAUL %@ · asked %.0f km wide x %.0f km tall · "
                + "RENDERED %.0f degrees of longitude across the frame",
            label, spanKm, spanKm * Double(heightPx) / Double(widthPx),
            Self.renderedLongitudeDeg(snapshot, center: center, widthPx: widthPx)
        ))
        print(String(
            format: "KAMOME_LONGHAUL %@ · mean %.1f · sd %.1f · %d buckets · "
                + "Taipei (%.0f, %.0f) %@ · Paris (%.0f, %.0f) %@%@",
            label, look.mean, look.sd, look.buckets,
            taipei.x, taipei.y, inside(taipei) ? "in" : "OUT",
            paris.x, paris.y, inside(paris) ? "in" : "OUT",
            failures.isEmpty ? "" : " (after \(failures.count) failures)"
        ))
    }

    /// **Where the boundary actually is**, for the pair that has no frame.
    ///
    /// Taipei→Paris fails before MapKit is reached: a 9:16 frame wide enough for
    /// a mostly east-west pair is 1.78x as tall, and past a certain width that
    /// height runs off the planet. So the limit is **Kamome's portrait frame**,
    /// not MapKit's tiles — and the two would be answered very differently.
    ///
    /// This walks the span up to that ceiling at the pair's own midpoint and
    /// reports, per step, whether a picture comes back and what is in it, so the
    /// threshold in `Docs/cross-region-journeys.md` is chosen from measurements
    /// rather than from the one span that happened to be tried.
    func testHowWideAPortraitFrameCanBeBeforeThereIsNoFrame() async throws {
        try requireProbe()
        let config = try exportConfig()
        let widthPx = config.frameWidthPx
        let heightPx = config.frameHeightPx
        let aspect = Double(heightPx) / Double(widthPx)
        let outDirectory = HarnessEnv.value("KAMOME_RENDER_OUT").map(URL.init(fileURLWithPath:))

        // 180 degrees of latitude is the whole planet; the frame is that tall
        // when its width is this.
        let ceilingM = 180 * 111_320 / aspect
        print(String(
            format: "KAMOME_LONGHAUL CEILING · a %dx%d frame is inexpressible as an MKCoordinateRegion "
                + "wider than %.0f km — and with wide_span_padding %.2f that is a pair %.0f km across",
            widthPx, heightPx, ceilingM / 1000, config.wideSpanPadding,
            ceilingM / config.wideSpanPadding / 1000
        ))

        // The Taipei-Paris midpoint: the case that has no frame, walked up to
        // the edge of the one it could have had.
        let center = CLLocationCoordinate2D(latitude: 36.9448, longitude: 61.9588)
        for spanKm in [4000.0, 6000, 8000, 10_000, 11_200] {
            for appearance in [RecapAppearance.light, .dark] {
                let label = String(format: "sweep-%.0fkm-%@", spanKm, "\(appearance)")
                let attempt = await Self.snapshot(
                    at: center, spanKm: spanKm, appearance: appearance,
                    widthPx: widthPx, heightPx: heightPx
                )
                guard let snapshot = attempt.snapshot else {
                    print("KAMOME_LONGHAUL \(label) — NO SNAPSHOT in 3 attempts: \(attempt.failures)")
                    continue
                }
                let failures = attempt.failures
                try report(
                    snapshot, label: label, spanKm: spanKm, center: center,
                    frame: (widthPx, heightPx), failures: failures
                )
                if let outDirectory {
                    let url = outDirectory.appendingPathComponent("longhaul-\(label).png")
                    try write(snapshot.image, to: url)
                }
            }
        }
    }

    /// **Is the wall MapKit's, or the portrait frame's?**
    ///
    /// The sweep above saturates at ~109 degrees of longitude while always
    /// asking for a 9:16 region, so it cannot separate "MapKit will not draw a
    /// wider picture" from "a 9:16 region wide enough is not askable". Those
    /// two answers lead to different designs, so this asks MapKit directly, at
    /// the same longitudinal spans but with a *short* latitudinal one — a region
    /// no Kamome frame would request, used only to find out whose limit it is.
    ///
    /// It renders into the shipped frame size regardless, because the size is
    /// not what is being tested.
    func testWhetherTheLongitudeCeilingBelongsToMapKitOrToThePortraitFrame() async throws {
        try requireProbe()
        let config = try exportConfig()
        let center = CLLocationCoordinate2D(latitude: 36.9448, longitude: 61.9588)
        let canvas = try MapKitSnapshotProvider.pointSize(
            widthPx: config.frameWidthPx, heightPx: config.frameHeightPx, displayScale: 1
        )
        for (longitudinalKm, latitudinalKm) in [(8000.0, 2000.0), (12_000.0, 2000.0), (16_000.0, 2000.0)] {
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: latitudinalKm * 1000, longitudinalMeters: longitudinalKm * 1000
            )
            options.size = canvas
            options.traitCollection = UITraitCollection(traitsFrom: [
                UITraitCollection(displayScale: 1), UITraitCollection(userInterfaceStyle: .light)
            ])
            do {
                let snapshot = try await MKMapSnapshotter(options: options).start()
                let west = snapshot.point(for: CLLocationCoordinate2D(
                    latitude: center.latitude, longitude: center.longitude - 45
                ))
                let east = snapshot.point(for: CLLocationCoordinate2D(
                    latitude: center.latitude, longitude: center.longitude + 45
                ))
                let degreesAcross = 90 * canvas.width / (east.x - west.x)
                print(String(
                    format: "KAMOME_LONGHAUL ASPECT · asked %.0f km wide x %.0f km tall (landscape) — "
                        + "RENDERED %.0f degrees of longitude",
                    longitudinalKm, latitudinalKm, degreesAcross
                ))
            } catch {
                print(String(
                    format: "KAMOME_LONGHAUL ASPECT · asked %.0f km wide x %.0f km tall — NO SNAPSHOT: %@",
                    longitudinalKm, latitudinalKm, "\(error)"
                ))
            }
        }
    }
}
