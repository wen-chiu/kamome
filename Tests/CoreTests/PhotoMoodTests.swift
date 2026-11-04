import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **What the photographs feel like, and where the film spent its time**
/// (`Docs/handoff-music-in-the-film.md` §2.3, §2.4). Synthetic places on the
/// shipped tunables, as `FilmCueSheetTests` builds them (§0).
final class PhotoMoodTests: XCTestCase {
    /// **The bit order is a storage format**: rows store these bits, so the
    /// list may only grow at its end. Reordering one label would read every
    /// stored photograph as another scene.
    func testTheLabelBitsAreAStorageFormat() {
        XCTAssertEqual(PhotoMood.Label.allCases.map(\.rawValue), [
            "mountain", "beach", "ocean", "shore", "snow", "sky", "forest", "waterfall", "lake", "glacier", "desert",
            "sunset_sunrise", "cityscape", "night_sky", "food", "people", "street", "restaurant"
        ])
        let labels: Set<PhotoMood.Label> = [.mountain, .nightSky, .restaurant]
        let mask = PhotoMood.Label.mask(labels)
        XCTAssertEqual(mask, 1 | (1 << 13) | (1 << 17))
        XCTAssertEqual(PhotoMood.Label.labels(in: mask), labels)
    }

    func testColourIsMeasuredFromThePixels() throws {
        let red: [UInt8] = [255, 0, 0, 255]
        let black: [UInt8] = [0, 0, 0, 255]
        let measured = try XCTUnwrap(PhotoMood.colour(rgba: red + black))
        XCTAssertEqual(measured.luminance, 0.2126 / 2, accuracy: 1e-9)
        XCTAssertEqual(measured.saturation, 0.5, accuracy: 1e-9, "black has no saturation")
        XCTAssertEqual(measured.warmth, 0.5, accuracy: 1e-9)
        XCTAssertNil(PhotoMood.colour(rgba: []))
    }

    func testSharesCountEachPhotographOnceAndADarkOneAsNight() {
        let mood = PhotoMood(photos: [
            .init(labels: PhotoMood.Label.mask([.mountain, .sky]), luminance: 0.5, saturation: 0.4, warmth: 0.1),
            .init(labels: PhotoMood.Label.mask([.food]), luminance: 0.6, saturation: 0.6, warmth: 0.3),
            .init(labels: 0, luminance: 0.05, saturation: 0.1, warmth: -0.2),
            .init(labels: PhotoMood.Label.mask([.nightSky]), luminance: 0.3, saturation: 0.2, warmth: 0)
        ], nightLuminanceMax: 0.18)
        XCTAssertEqual(mood.photoCount, 4)
        XCTAssertEqual(mood.landscapeShare, 0.25)
        XCTAssertEqual(mood.peopleShare, 0.25)
        XCTAssertEqual(mood.nightShare, 0.5, "the night label, and a photograph under the luminance line")
        XCTAssertEqual(mood.luminance, (0.5 + 0.6 + 0.05 + 0.3) / 4, accuracy: 1e-12)
    }

    // MARK: - Film time per country

    typealias Place = RecapCoordinate

    private func trip(_ places: [Place], countries: [String?], crossings: Set<Int> = []) -> RecapTrip {
        let stops = places.enumerated().map { index, place in
            RecapTrip.Stop(coordinate: place, name: "Stop \(index)", dayLabel: "Day 1",
                           photos: (0..<3).map { .asset("p\(index)-\($0)") }, dwellS: 3600,
                           locality: "Town \(index)", countryCode: countries[index])
        }
        let legs = zip(places, places.dropFirst()).enumerated().map { index, pair -> RecapTrip.Leg in
            let crossing = crossings.contains(index)
            let coordinates = crossing ? [pair.0, pair.1] : (0...30).map { step in
                Place(lat: pair.0.lat + (pair.1.lat - pair.0.lat) * Double(step) / 30,
                      lon: pair.0.lon + (pair.1.lon - pair.0.lon) * Double(step) / 30)
            }
            return RecapTrip.Leg(coordinates: coordinates, mode: .drive, provenance: crossing ? .inferred : .reconstructed,
                                 isCrossing: crossing,
                                 countryCodes: crossing ? (countries[index], countries[index + 1]) : (nil, nil))
        }
        return RecapTrip(legs: legs, stops: stops, title: "Trip", subtitle: "", endCardFigures: [],
                         everyLegRoutabilityEstablished: true)
    }

    private func timeline(_ trip: RecapTrip) throws -> LinearTimeline {
        try XCTUnwrap(LinearTimeline(trip: trip, config: SoundtrackTestSupport.shipped().export,
                                     locale: Locale(identifier: "en")))
    }

    func testFilmTimeIsSharedByTheStopsCountries() throws {
        let places = (0..<4).map { Place(lat: 38.7 + Double($0) * 0.3, lon: -9.1 + Double($0) * 0.1) }
        let film = try timeline(trip(places, countries: ["AA", "AA", "BB", nil]))
        let countries = film.soundtrackCountries()
        XCTAssertEqual(countries.destination, "BB", "the last stop with a country")
        XCTAssertEqual(Set(countries.share.keys), ["AA", "BB"], "a stop with no country is not counted")
        XCTAssertEqual(countries.share.values.reduce(0, +), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(countries.share["AA"] ?? 0, countries.share["BB"] ?? 0)
    }

    func testAFlightFilmCountsOnlyTheFarSide() throws {
        let home = Place(lat: 1.36, lon: 103.99)
        let far = (0..<4).map { Place(lat: 51.47 + Double($0) * 0.1, lon: -0.45 - Double($0) * 0.25) }
        let film = try timeline(trip([home] + far, countries: ["AA", "BB", "BB", "BB", "BB"], crossings: [0]))
        XCTAssertTrue(film.filmType.hasDestinationAbroad)
        XCTAssertEqual(film.soundtrackCountries().share, ["BB": 1])
    }
}
