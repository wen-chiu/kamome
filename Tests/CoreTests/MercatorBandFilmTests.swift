import CoreGraphics
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **A film that holds places continents apart exports; every other film is
/// untouched** (#223, ADR 2026-10-07). The stations are checked on the
/// projection MapLibre really draws — a frame past ±85.05° shifted back inside,
/// one taller than the world zoomed in, both measured on #223.
final class MercatorBandFilmTests: XCTestCase {
    private typealias Place = RecapCoordinate

    private func shipped() throws -> TrackingConfig.Export {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
        return try TrackingConfigLoader.load(contentsOf: url).export
    }

    // Public places only (§0) — synthetic geometry, never a real trip.
    private let taipei = Place(lat: 25.08, lon: 121.23)

    private func loop(_ centre: Place) -> [Place] {
        [centre, Place(lat: centre.lat + 0.4, lon: centre.lon + 0.4),
         Place(lat: centre.lat - 0.4, lon: centre.lon + 0.6), Place(lat: centre.lat, lon: centre.lon - 0.4)]
    }

    /// Stops in order; `crossings` are the legs (i → i+1) with no road.
    private func trip(_ places: [Place], crossings: Set<Int>) -> RecapTrip {
        let stops = places.enumerated().map { index, place in
            RecapTrip.Stop(
                coordinate: place, name: "S\(index)", dayLabel: "D",
                photos: [.asset("a\(index)"), .asset("b\(index)")], dwellS: 3600, locality: "T\(index)"
            )
        }
        let legs = zip(places, places.dropFirst()).enumerated().map { index, pair in
            RecapTrip.Leg(
                coordinates: crossings.contains(index)
                    ? [pair.0, pair.1]
                    : (0...30).map { step in
                        let fraction = Double(step) / 30
                        return Place(lat: pair.0.lat + (pair.1.lat - pair.0.lat) * fraction,
                                     lon: pair.0.lon + (pair.1.lon - pair.0.lon) * fraction)
                    },
                mode: .drive, provenance: .reconstructed, isCrossing: crossings.contains(index)
            )
        }
        return RecapTrip(
            legs: legs, stops: stops, title: "T", subtitle: "", endCardFigures: [],
            everyLegRoutabilityEstablished: true
        )
    }

    /// Taipei, a loop near Tokyo, a loop near Vancouver, home: an end reveal and
    /// arcs over the North Pacific, wide enough to reach past 85°N.
    private var intercontinental: RecapTrip {
        let places = [taipei] + loop(Place(lat: 35.68, lon: 139.69)) + loop(Place(lat: 49.28, lon: -123.12)) + [taipei]
        return trip(places, crossings: [0, 4, 8])
    }

    private func timeline(_ trip: RecapTrip, band: Bool, config: TrackingConfig.Export) throws -> LinearTimeline {
        try XCTUnwrap(LinearTimeline(trip: trip, config: config, locale: Locale(identifier: "en"))).fitted(
            into: band ? MercatorBand(
                maxLatitudeDeg: MercatorBand.webMercatorMaxLatitudeDeg,
                widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
            ) : nil
        )
    }

    func testAnIntercontinentalFilmExportsWithTheBand() throws {
        let config = try shipped()
        let fitted = try timeline(intercontinental, band: true, config: config)
        XCTAssertGreaterThan(fitted.framesFittedIntoBand(fps: config.fps).moved, 0, "precondition: frames reach past the edge")
        XCTAssertEqual(try containmentFailures(fitted, config: config), 0)
    }

    /// The same film without the band is the failure #223 reported — so the
    /// test above can fail.
    func testWithoutTheBandTheSameFilmFails() throws {
        let config = try shipped()
        XCTAssertGreaterThan(try containmentFailures(timeline(intercontinental, band: false, config: config), config: config), 0)
    }

    /// A film inside the band is the same film, frame for frame and station for
    /// station — the band costs nothing where it is not needed.
    func testAFilmInsideTheBandIsUnchanged() throws {
        let config = try shipped()
        let local = trip(loop(Place(lat: 64.15, lon: -21.94)) + loop(Place(lat: 65.68, lon: -18.09)), crossings: [])
        let plain = try timeline(local, band: false, config: config)
        let banded = try timeline(local, band: true, config: config)
        XCTAssertEqual(banded.framesFittedIntoBand(fps: config.fps).moved, 0)
        for frame in 0..<plain.frameCount {
            let time = Double(frame) / Double(config.fps)
            XCTAssertEqual(banded.cameraFrame(atTime: time), plain.cameraFrame(atTime: time))
        }
        XCTAssertEqual(stations(banded, config: config), stations(plain, config: config))
    }

    // MARK: - Measuring

    private func stations(_ line: LinearTimeline, config: TrackingConfig.Export) -> [RecapSnapshotStations.Station] {
        let camera = { (time: Double) in line.cameraFrame(atTime: time) }
        return RecapSnapshotStations.plan(
            frameCount: line.frameCount, fps: config.fps, camera: camera, map: { line.mapState(atTime: $0) },
            mustStartAt: RecapSnapshotStations.splitFrames(
                holds: line.holds, frameCount: line.frameCount, fps: config.fps, camera: camera
            ),
            config: config, band: line.substrateBand
        )
    }

    /// Frames a station cannot serve, each station drawn the way MapLibre draws
    /// it — shifted inside ±85.05°, zoomed in when taller than the world.
    private func containmentFailures(_ line: LinearTimeline, config: TrackingConfig.Export) throws -> Int {
        let width = config.frameWidthPx, height = config.frameHeightPx
        let substrate = MercatorBand(
            maxLatitudeDeg: MercatorBand.webMercatorMaxLatitudeDeg, widthPx: width, heightPx: height
        )
        let pixel = try XCTUnwrap(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage())
        var failures = 0
        for station in stations(line, config: config) {
            let drawn = substrate.fitted(station.camera)
            let world = substrate.worldPx(drawn)
            let snapshot = MapSnapshot(image: pixel) { lat, lon in
                CGPoint(
                    x: (lon - drawn.centerLon) / 360 * world + Double(width) / 2,
                    y: (MercatorBand.mercatorY(lat) - MercatorBand.mercatorY(drawn.centerLat)) * world + Double(height) / 2
                )
            }
            for frame in station.frames where (try? SnapshotReprojection(
                station: snapshot, stationCamera: station.camera,
                target: line.cameraFrame(atTime: Double(frame) / Double(config.fps)),
                widthPx: width, heightPx: height
            )) == nil {
                failures += 1
            }
        }
        return failures
    }
}
