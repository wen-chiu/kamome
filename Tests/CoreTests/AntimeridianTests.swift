import CoreGraphics
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **A trip across 180° is framed the short way** (#234, ADR 2026-10-07).
///
/// Before: Tokyo to Vancouver measured 263° the long way round, the film asked
/// for frames 44,338 km wide over the wrong hemisphere, and with #223's band
/// 1,770 stop positions the frames should have shown fell outside them.
final class AntimeridianTests: XCTestCase {
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

    /// Stops in order, joined by straight legs taken the short way and stored
    /// in ordinary longitudes, as the app stores them; `crossings` are legs
    /// with no road.
    private func trip(_ places: [Place], crossings: Set<Int> = []) -> RecapTrip {
        let stops = places.enumerated().map { index, place in
            RecapTrip.Stop(
                coordinate: place, name: "S\(index)", dayLabel: "D",
                photos: [.asset("a\(index)"), .asset("b\(index)")], dwellS: 3600, locality: "T\(index)"
            )
        }
        let legs = zip(places, places.dropFirst()).enumerated().map { index, pair -> RecapTrip.Leg in
            let eastward = Antimeridian.normalized(pair.1.lon - pair.0.lon)
            let coordinates = crossings.contains(index) ? [pair.0, pair.1] : (0...30).map { step in
                let fraction = Double(step) / 30
                return Place(
                    lat: pair.0.lat + (pair.1.lat - pair.0.lat) * fraction,
                    lon: Antimeridian.normalized(pair.0.lon + eastward * fraction)
                )
            }
            return RecapTrip.Leg(
                coordinates: coordinates, mode: .drive, provenance: .reconstructed,
                isCrossing: crossings.contains(index)
            )
        }
        return RecapTrip(
            legs: legs, stops: stops, title: "T", subtitle: "", endCardFigures: [],
            everyLegRoutabilityEstablished: true
        )
    }

    private var pacific: RecapTrip {
        trip([taipei] + loop(Place(lat: 35.68, lon: 139.69)) + loop(Place(lat: 49.28, lon: -123.12)) + [taipei],
             crossings: [0, 4, 8])
    }

    // MARK: - The seam

    func testNormalizedLongitudesLieInTheOrdinaryRange() {
        XCTAssertEqual(Antimeridian.normalized(236.88), -123.12, accuracy: 1e-9)
        XCTAssertEqual(Antimeridian.normalized(-190), 170, accuracy: 1e-9)
        XCTAssertEqual(Antimeridian.normalized(180), -180, accuracy: 1e-9)
        XCTAssertEqual(Antimeridian.normalized(42), 42, accuracy: 1e-9)
    }

    /// Every trip that never crosses 180° comes back as the identical value —
    /// which is what keeps every other film unchanged.
    func testATripThatDoesNotCrossTheMeridianIsUntouched() {
        let iceland = trip(loop(Place(lat: 64.15, lon: -21.94)) + loop(Place(lat: 65.68, lon: -18.09)))
        let eurasia = trip([taipei] + loop(Place(lat: 37.56, lon: 126.97)) + loop(Place(lat: 64.15, lon: -21.94)),
                           crossings: [0, 4])
        for trip in [iceland, eurasia] {
            let unwrapped = trip.unwrappedAcrossTheAntimeridian()
            XCTAssertEqual(unwrapped.legs, trip.legs)
            XCTAssertEqual(unwrapped.stops, trip.stops)
        }
    }

    /// Vancouver joins the trip east of Tokyo rather than 263° west of it.
    func testAPacificTripBecomesContinuous() {
        let longitudes = pacific.unwrappedAcrossTheAntimeridian().stops.map(\.coordinate.lon)
        XCTAssertEqual(longitudes.first, taipei.lon)
        XCTAssertEqual(longitudes[5], 236.88, accuracy: 1e-9)
        XCTAssertLessThan((longitudes.max() ?? 0) - (longitudes.min() ?? 0), 120, "the short way across the Pacific")
    }

    // MARK: - The films

    func testAPacificFilmIsFramedOverThePacificAndLosesNoStop() throws {
        let config = try shipped()
        let band = MercatorBand(
            maxLatitudeDeg: MercatorBand.webMercatorMaxLatitudeDeg,
            widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
        )
        let line = try XCTUnwrap(LinearTimeline(trip: pacific, config: config, locale: Locale(identifier: "en")))
            .fitted(into: band)
        let stops = pacific.unwrappedAcrossTheAntimeridian().stops.map(\.coordinate)
        var widest = 0.0
        for frame in 0..<line.frameCount {
            let time = Double(frame) / Double(config.fps)
            let raw = line.path.cameraFrame(atTime: time)
            let asked = CameraFrame(centerLat: raw.centerLat, centerLon: raw.centerLon, spanM: raw.spanM, bearing: 0)
            widest = max(widest, asked.spanM)
            // Whatever the band does to a frame, a stop the camera asked to
            // show is still in the picture.
            let drawn = line.cameraFrame(atTime: time)
            for stop in stops where Self.shows(asked, stop, band: band) {
                XCTAssertTrue(Self.shows(drawn, stop, band: band), "frame \(frame) lost a stop")
            }
        }
        XCTAssertLessThan(widest, 20_000_000, "it asked for 44,338 km before #234")
    }

    /// A local trip on 180° itself (synthetic, Fiji's longitude) is framed as
    /// the island it is, not as the whole world.
    func testALocalTripOnTheMeridianIsFramedLocally() throws {
        let config = try shipped()
        let island = trip([
            Place(lat: -16.80, lon: 179.70), Place(lat: -16.90, lon: 179.95), Place(lat: -16.95, lon: -179.90),
            Place(lat: -16.70, lon: -179.80), Place(lat: -16.80, lon: 179.80)
        ])
        let line = try XCTUnwrap(LinearTimeline(trip: island, config: config, locale: Locale(identifier: "en")))
        let widest = (0..<line.frameCount).map { line.cameraFrame(atTime: Double($0) / Double(config.fps)).spanM }.max()
        XCTAssertLessThan(try XCTUnwrap(widest), 1_000_000)
    }

    /// The flight's width is measured the short way: Taipei to Tonga is 64°
    /// across the Pacific, inside the drawn-flight policy, not 296°.
    func testAFlightAcrossTheMeridianIsMeasuredTheShortWay() throws {
        let config = try shipped()
        let tonga = trip([taipei] + loop(Place(lat: -21.14, lon: -175.20)) + [taipei], crossings: [0, 4])
        let line = try XCTUnwrap(LinearTimeline(trip: tonga, config: config, locale: Locale(identifier: "en")))
        XCTAssertTrue(line.opensOnTheFlight)
    }

    /// Whether `point` is inside the picture a substrate draws for `frame`,
    /// taking the copy nearest the centre as MapLibre does (VERIFIED, #234).
    private static func shows(_ frame: CameraFrame, _ point: Place, band: MercatorBand) -> Bool {
        let world = band.worldPx(frame)
        var dx = (point.lon - frame.centerLon) / 360 * world
        dx -= (dx / world).rounded() * world
        let dy = (MercatorBand.mercatorY(point.lat) - MercatorBand.mercatorY(frame.centerLat)) * world
        return abs(dx) <= Double(band.widthPx) / 2 && abs(dy) <= Double(band.heightPx) / 2
    }
}
