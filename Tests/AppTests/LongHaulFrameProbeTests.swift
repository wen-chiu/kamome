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

/// **Does a frame containing two places on opposite sides of a flight exist?**
///
/// Written 2026-09-01 for the type-2 (home → one destination abroad) film. Every
/// candidate opening that *draws* the flight needs one frame holding both
/// endpoints at once, and nobody had ever asked MapKit for one at long-haul
/// scale. Designing the opening around a guess about that frame is what this
/// exists to prevent.
///
/// It is a **probe, not a gate**: it asserts only the two things that would make
/// its own numbers meaningless (a snapshot came back, and the projection is the
/// one `MapKitSnapshotProvider` promises). Everything else is printed, because
/// "is this a usable picture" is a look and is judged by looking — which is why
/// it also writes the PNGs.
///
/// Needs the network (Apple Maps tiles), so it is env-gated like every other
/// live-substrate harness in this target:
///
///   TEST_RUNNER_KAMOME_LONGHAUL_PROBE=1 \
///   TEST_RUNNER_KAMOME_RENDER_OUT=/path/to/out \
///   xcodebuild -scheme Kamome test -destination '…' \
///     -only-testing:KamomeTests/LongHaulFrameProbeTests
final class LongHaulFrameProbeTests: XCTestCase {
    /// Public city coordinates, never a fixture or a real dump (`CLAUDE.md` §0).
    /// Rounded to four decimals: these name cities, not places anyone has been.
    private struct Place {
        let name: String
        let coordinate: CLLocationCoordinate2D

        init(_ name: String, _ lat: Double, _ lon: Double) {
            self.name = name
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }

    private static let taipei = Place("Taipei", 25.0330, 121.5654)

    /// The distances the type-2 design has to survive, shortest first.
    ///
    /// **Auckland and Moscow were added 2026-09-02 to fill the gap the threshold
    /// sits in.** The policy of 70° is interpolated between two measurements 67°
    /// apart — Sydney at 29.6° (a good shot) and Helsinki at 96.6° (framed, and
    /// visually useless) — with nothing rendered in between. Auckland is the
    /// nearest real pair above Sydney (`CountryExtent` puts the Taiwan–New Zealand
    /// envelope at 59.3°); Moscow at 83.9° sits **above** the proposed threshold,
    /// so the rule can be judged on what it excludes and not only on what it
    /// admits.
    ///
    /// The last two were added 2026-09-01 at Chiu's request, and they are not
    /// hypothetical: **Iceland and Finland are two of the six rows in
    /// `CountryExtent`**, and the Iceland film is the Geoapify acceptance trip —
    /// the most-judged film in the repository. Taiwan → Iceland is expected to
    /// have no frame; Taiwan → Finland is expected to pass with little margin,
    /// which is what decides whether the rule needs headroom or a hard edge.
    private static let pairs: [(Place, Place)] = [
        (taipei, Place("Ishigaki", 24.3448, 124.1572)),
        (taipei, Place("Tokyo", 35.6762, 139.6503)),
        (taipei, Place("Sydney", -33.8688, 151.2093)),
        (taipei, Place("Auckland", -36.8485, 174.7633)),
        (taipei, Place("Moscow", 55.7558, 37.6176)),
        (taipei, Place("Helsinki", 60.1699, 24.9384)),
        (taipei, Place("Reykjavik", 64.1466, -21.9426)),
        (taipei, Place("Paris", 48.8566, 2.3522))
    ]

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

    /// What a flat picture looks like as numbers, so "grey" is reported rather
    /// than asserted. A frame of open ocean has almost no luminance spread and
    /// nearly every pixel in one bucket; a frame with coastlines and labels does
    /// not.
    private struct Content {
        let meanLuminance: Double
        let standardDeviation: Double
        /// Share of pixels in the single most common of 256 luminance buckets.
        let modalShare: Double
        /// How many buckets hold at least 0.1% of the picture.
        let occupiedBuckets: Int
    }

    private func content(of image: CGImage) throws -> Content {
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
        return Content(
            meanLuminance: mean,
            standardDeviation: sqrt(variance),
            modalShare: Double(histogram.max() ?? 0) / total,
            occupiedBuckets: histogram.filter { $0 >= floorCount }.count
        )
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "PNG write failed")
    }

    /// One snapshot per pair per appearance, at the shipped frame, through the
    /// shipped provider — then report what came back and where the two places
    /// actually landed in it.
    func testWhatMapKitReturnsForAFrameHoldingBothEndsOfAFlight() async throws {
        try requireProbe()
        let config = try exportConfig()
        let outDirectory = HarnessEnv.value("KAMOME_RENDER_OUT").map(URL.init(fileURLWithPath:))
        if let outDirectory {
            try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
        }
        // Two paddings per pair, not one. `wide_span_padding` 1.5 is what beat 2
        // uses, and for a high-latitude east-west pair it is the difference
        // between a frame and no frame — so measuring only the padded one would
        // report "impossible" for a pair that is merely impossible *with room to
        // spare around it*. 1.0 is the tightest frame that still holds both ends.
        for (origin, destination) in Self.pairs {
            for padding in [config.wideSpanPadding, 1.0] {
                try await probe(origin, destination, padding: padding, into: outDirectory)
            }
        }
    }

    /// One pair at one padding, in both appearances.
    private func probe(
        _ origin: Place, _ destination: Place, padding: Double, into outDirectory: URL?
    ) async throws {
        let config = try exportConfig()
        let widthPx = config.frameWidthPx
        let heightPx = config.frameHeightPx
        let bounds = CameraPath.Bounds(
            minLat: min(origin.coordinate.latitude, destination.coordinate.latitude),
            maxLat: max(origin.coordinate.latitude, destination.coordinate.latitude),
            minLon: min(origin.coordinate.longitude, destination.coordinate.longitude),
            maxLon: max(origin.coordinate.longitude, destination.coordinate.longitude)
        )
        let frame = CameraPath.frame(for: bounds, config: config, padding: padding)
        let paddingLabel = String(format: "pad%.2f", padding)
        let apartKm = Geo.distanceM(
            latA: origin.coordinate.latitude, lonA: origin.coordinate.longitude,
            latB: destination.coordinate.latitude, lonB: destination.coordinate.longitude
        ) / 1000
        // The longitude the pair actually spans — the quantity the threshold is
        // in, and the one a kilometre figure hides.
        let longitudeApart = abs(origin.coordinate.longitude - destination.coordinate.longitude)

        guard Self.isFramable(
            frame, label: "\(origin.name)-\(destination.name)-\(paddingLabel)",
            apartKm: apartKm, longitudeApart: longitudeApart, widthPx: widthPx, heightPx: heightPx
        ) else { return }

        for appearance in [RecapAppearance.light, .dark] {
            let label = "\(origin.name)-\(destination.name)-\(paddingLabel)-\(appearance)"
            let attempt = await Self.snapshot(
                frame, appearance: appearance, widthPx: widthPx, heightPx: heightPx
            )
            guard let snapshot = attempt.snapshot else {
                print("KAMOME_LONGHAUL \(label) — NO SNAPSHOT in 3 attempts: \(attempt.failures)")
                continue
            }
            if !attempt.failures.isEmpty {
                print("KAMOME_LONGHAUL \(label) — succeeded on attempt \(attempt.failures.count + 1)")
            }
            try report(
                snapshot, label: label, frame: frame, places: (origin, destination),
                apartKm: apartKm, longitudeApart: longitudeApart
            )
            if let outDirectory {
                let url = outDirectory.appendingPathComponent("longhaul-\(label).png")
                try write(snapshot.image, to: url)
                print("KAMOME_LONGHAUL \(label) · wrote \(url.path)")
            }
            assertTheProbeIsMeaningful(snapshot, label: label, places: (origin, destination))
        }
    }

    /// The only assertions in the pair probe. A snapshot whose projection is not
    /// the provider's, or whose two ends land on one point, prints numbers that
    /// mean nothing — everything else here is a look, and is judged by looking.
    private func assertTheProbeIsMeaningful(
        _ snapshot: MapSnapshot, label: String, places: (origin: Place, destination: Place)
    ) {
        let config = try? exportConfig()
        guard let config else { return XCTFail("\(label): the shipped config did not load") }
        XCTAssertEqual(
            snapshot.image.width,
            config.frameWidthPx * snapshot.image.height / config.frameHeightPx
        )
        XCTAssertNotEqual(
            snapshot.point(
                lat: places.origin.coordinate.latitude, lon: places.origin.coordinate.longitude
            ),
            snapshot.point(
                lat: places.destination.coordinate.latitude,
                lon: places.destination.coordinate.longitude
            ),
            "\(label): both endpoints projected to one point — the frame cannot show a flight"
        )
    }

    /// Ask the provider whether it can draw this frame at all, rather than
    /// re-deriving its rules here — and report the refusal as a row.
    ///
    /// Before 2026-09-01 this was an uncatchable Objective-C exception that took
    /// the process with it, which is the only reason this probe can reach
    /// Iceland at all.
    private static func isFramable(
        _ frame: CameraPath.CameraFrame, label: String,
        apartKm: Double, longitudeApart: Double, widthPx: Int, heightPx: Int
    ) -> Bool {
        do {
            _ = try MapKitSnapshotProvider.region(
                centerLat: frame.centerLat, centerLon: frame.centerLon,
                spanM: frame.spanM, widthPx: widthPx, heightPx: heightPx
            )
            return true
        } catch {
            print(String(
                format: "KAMOME_LONGHAUL %@ · %.0f km apart · %.1f deg of longitude · "
                    + "frame span %.0f km (%.0f km tall) · *** NO FRAME: %@ ***",
                label, apartKm, longitudeApart, frame.spanM / 1000,
                frame.spanM / 1000 * Double(heightPx) / Double(widthPx), "\(error)"
            ))
            return false
        }
    }

    /// Three attempts, and the failures kept: a single failure cannot tell a
    /// scale MapKit refuses from a tile server having a bad minute, and the
    /// difference decides a design question. Taipei→Tokyo failed once in eight
    /// on 2026-09-01 and succeeded on the retry.
    private static func snapshot(
        _ frame: CameraPath.CameraFrame, appearance: RecapAppearance, widthPx: Int, heightPx: Int
    ) async -> (snapshot: MapSnapshot?, failures: [String]) {
        let provider = MapKitSnapshotProvider(appearance: appearance)
        let cameraFrame = CameraFrame(
            centerLat: frame.centerLat, centerLon: frame.centerLon, spanM: frame.spanM, bearing: 0
        )
        var snapshot: MapSnapshot?
        var failures: [String] = []
        for _ in 1...3 where snapshot == nil {
            do {
                snapshot = try await provider.snapshot(
                    cameraFrame, map: MapState(), widthPx: widthPx, heightPx: heightPx
                )
            } catch {
                failures.append("\(error)")
            }
        }
        return (snapshot, failures)
    }

    /// One pair's row: what came back, where the two places landed, and how far
    /// Mercator moved them from where a flat model would put them.
    private func report(
        _ snapshot: MapSnapshot, label: String, frame: CameraPath.CameraFrame,
        places: (origin: Place, destination: Place), apartKm: Double, longitudeApart: Double
    ) throws {
        let config = try exportConfig()
        let widthPx = config.frameWidthPx
        let heightPx = config.frameHeightPx
        let originPoint = snapshot.point(
            lat: places.origin.coordinate.latitude, lon: places.origin.coordinate.longitude
        )
        let destinationPoint = snapshot.point(
            lat: places.destination.coordinate.latitude, lon: places.destination.coordinate.longitude
        )
        let inside = { (point: CGPoint) in
            point.x >= 0 && point.x <= Double(widthPx) && point.y >= 0 && point.y <= Double(heightPx)
        }
        let look = try content(of: snapshot.image)

        // Mercator's y is not linear in ground metres, so a frame sized from a
        // ground span puts a high-latitude endpoint somewhere a flat model does
        // not predict. The gap between the two is the distortion.
        let verticalSpanM = frame.spanM * Double(heightPx) / Double(widthPx)
        let flatModelY = { (lat: Double) -> Double in
            let northM = Geo.distanceM(
                latA: frame.centerLat, lonA: frame.centerLon, latB: lat, lonB: frame.centerLon
            ) * (lat >= frame.centerLat ? 1 : -1)
            return Double(heightPx) / 2 - northM / verticalSpanM * Double(heightPx)
        }
        let originSkew = abs(originPoint.y - flatModelY(places.origin.coordinate.latitude))
        let destinationSkew = abs(destinationPoint.y - flatModelY(places.destination.coordinate.latitude))

        print(String(
            format: "KAMOME_LONGHAUL %@ · %.0f km apart · %.1f deg of longitude · "
                + "frame span %.0f km (%.0f km tall) · image %dx%dpx",
            label, apartKm, longitudeApart, frame.spanM / 1000, verticalSpanM / 1000,
            snapshot.image.width, snapshot.image.height
        ))
        print(String(
            format: "KAMOME_LONGHAUL %@ · %@ at (%.0f, %.0f) %@ · %@ at (%.0f, %.0f) %@",
            label, places.origin.name, originPoint.x, originPoint.y,
            inside(originPoint) ? "INSIDE" : "*** OUTSIDE THE FRAME ***",
            places.destination.name, destinationPoint.x, destinationPoint.y,
            inside(destinationPoint) ? "INSIDE" : "*** OUTSIDE THE FRAME ***"
        ))
        print(String(
            format: "KAMOME_LONGHAUL %@ · mercator skew %.0f px / %.0f px (%.1f%% / %.1f%% of height)",
            label, originSkew, destinationSkew,
            originSkew / Double(heightPx) * 100, destinationSkew / Double(heightPx) * 100
        ))
        print(String(
            format: "KAMOME_LONGHAUL %@ · mean luminance %.1f · sd %.1f · modal bucket %.1f%% · "
                + "%d buckets occupied",
            label, look.meanLuminance, look.standardDeviation,
            look.modalShare * 100, look.occupiedBuckets
        ))
    }
}
