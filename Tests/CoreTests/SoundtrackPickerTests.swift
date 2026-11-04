import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **Which music, decided by us** (`Docs/handoff-music-in-the-film.md` §2.3).
/// The style comes from the country, the mood from the photographs and the
/// film's shape, the take from the seed; deterministic, and never a track that
/// cannot fill the film. Countries are read from the shipped table, never
/// written here, so no test names a trip (§0).
final class SoundtrackPickerTests: XCTestCase {
    private func config() throws -> TrackingConfig.Soundtrack { try SoundtrackTestSupport.soundtrack() }

    /// A listed country and the style the shipped table gives it.
    private func listed(_ index: Int) throws -> (country: String, style: String) {
        let row = try config().countryStyles[index]
        return (try XCTUnwrap(row.countries.first), row.style)
    }

    private let unlisted = "ZZ"

    private func context(
        share: [String: Double] = [:], destination: String? = nil, mood: PhotoMood = .neutral,
        filmType: RecapFilmType = .local, durationS: Double = 90, appearance: RecapAppearance = .light,
        seed: UInt64 = 0
    ) -> SoundtrackContext {
        SoundtrackContext(countryShare: share, destinationCountry: destination, photoMood: mood, filmType: filmType,
                          durationS: durationS, appearance: appearance, seed: seed)
    }

    /// The synthetic track renamed: same grid and sections, another identity.
    private func track(_ id: String, style: String, mood: SoundtrackMood, repeatable: Bool = true) -> SoundtrackManifest {
        let base = SyntheticSoundtrack.manifest
        let sections = base.sections.map {
            SoundtrackManifest.Section(name: $0.name, startBar: $0.startBar, bars: $0.bars, energy: $0.energy,
                                       role: $0.role, repeatable: repeatable && $0.repeatable)
        }
        return SoundtrackManifest(
            id: id, style: style, mood: mood.rawValue, file: id + ".m4a", durationS: base.durationS, bpm: base.bpm,
            beatsPerBar: base.beatsPerBar, firstDownbeatS: base.firstDownbeatS, tempoDriftBpm: base.tempoDriftBpm,
            sections: sections, sectionsConfirmed: false, finalHitBar: base.finalHitBar, tailS: base.tailS,
            integratedLufs: base.integratedLufs, truePeakDbtp: base.truePeakDbtp, provenance: base.provenance
        )
    }

    // MARK: - Style

    func testTheCountryWithTheMostFilmTimePicksTheStyle() throws {
        let (first, second) = (try listed(0), try listed(1))
        let style = SoundtrackPicker.style(
            for: context(share: [first.country: 0.3, second.country: 0.7], destination: first.country),
            config: try config()
        )
        XCTAssertEqual(style, second.style)
    }

    func testATieAndAFlightFilmGoToTheDestination() throws {
        let (first, second) = (try listed(0), try listed(1))
        let tie = context(share: [first.country: 0.5, second.country: 0.5], destination: second.country)
        XCTAssertEqual(SoundtrackPicker.style(for: tie, config: try config()), second.style)
        // A flight film: the home end's share does not count.
        let flight = context(share: [first.country: 0.9, second.country: 0.1], destination: second.country,
                             filmType: .oneDestination)
        XCTAssertEqual(SoundtrackPicker.style(for: flight, config: try config()), second.style)
    }

    func testAnUnlistedCountryAndNoCountryPlayTheUnlistedStyle() throws {
        let config = try config()
        XCTAssertEqual(SoundtrackPicker.style(for: context(share: [unlisted: 1]), config: config), config.unlistedStyle)
        XCTAssertEqual(SoundtrackPicker.style(for: context(), config: config), config.unlistedStyle)
    }

    // MARK: - Mood

    private func photos(_ count: Int, labels: [PhotoMood.Label], luminance: Double, saturation: Double,
                        warmth: Double = 0) throws -> PhotoMood {
        PhotoMood(photos: Array(repeating: PhotoMood.Photo(labels: PhotoMood.Label.mask(labels), luminance: luminance,
                                                           saturation: saturation, warmth: warmth), count: count),
                  nightLuminanceMax: try config().mood.nightLuminanceMax)
    }

    private func winner(_ context: SoundtrackContext) throws -> SoundtrackMood? {
        let scores = SoundtrackPicker.moodScores(for: context, config: try config())
        return scores.max { $0.value < $1.value }?.key
    }

    func testLandscapesLeanEpic() throws {
        let mood = try photos(10, labels: [.mountain, .waterfall], luminance: 0.45, saturation: 0.45)
        XCTAssertEqual(try winner(context(mood: mood)), .epic)
    }

    func testPeopleInBrightColourLeanDepart() throws {
        let mood = try photos(10, labels: [.people, .food], luminance: 0.6, saturation: 0.6, warmth: 0.2)
        XCTAssertEqual(try winner(context(mood: mood)), .depart)
    }

    func testNightLeansCruise() throws {
        let mood = try photos(10, labels: [.nightSky], luminance: 0.1, saturation: 0.2)
        XCTAssertEqual(try winner(context(mood: mood, appearance: .dark)), .cruise)
    }

    /// No photograph measured is not a dull film: colour pushes nothing, and the
    /// film's shape alone decides.
    func testUnmeasuredPhotographsPushNoMood() throws {
        let config = try config()
        let scores = SoundtrackPicker.moodScores(for: context(), config: config)
        XCTAssertEqual(scores[.cruise], config.mood.baseCruise)
        XCTAssertEqual(scores[.depart], config.mood.baseDepart)
        let longFlight = context(filmType: .oneDestination, durationS: config.mood.longFilmS)
        let flight = SoundtrackPicker.moodScores(for: longFlight, config: config)
        XCTAssertEqual(flight[.epic], config.mood.baseEpic + config.mood.flightEpic + config.mood.longFilmEpic)
    }

    // MARK: - Ranking

    private func catalog(style: String) -> [SoundtrackManifest] {
        SoundtrackMood.allCases.flatMap { mood in
            [track("\(style)-\(mood.rawValue)-a", style: style, mood: mood),
             track("\(style)-\(mood.rawValue)-b", style: style, mood: mood)]
        }
    }

    func testOneTakePerMoodComesFirstInTheOrderTheMoodsScored() throws {
        let (country, style) = try listed(0)
        let other = try listed(1).style
        let ranking = SoundtrackPicker.rank(
            catalog: catalog(style: style) + catalog(style: other),
            context: context(share: [country: 1], mood: try photos(10, labels: [.mountain], luminance: 0.45, saturation: 0.45)),
            cues: SoundtrackTestSupport.cues(durationS: 90), config: try config()
        )
        XCTAssertFalse(ranking.styleFellBack)
        XCTAssertEqual(ranking.choices.count, 6, "every take of the trip's style, and no other style")
        XCTAssertTrue(ranking.choices.allSatisfy { $0.manifest.style == style })
        XCTAssertEqual(Set(ranking.choices.prefix(3).map(\.mood)).count, 3, "three different moods first")
        XCTAssertEqual(ranking.choices.first?.mood, .epic)
    }

    func testTheSeedPicksTheTakeAndTheSameTripAlwaysGetsTheSameOne() throws {
        let (country, style) = try listed(0)
        func first(_ seed: UInt64) throws -> String? {
            SoundtrackPicker.rank(catalog: catalog(style: style), context: context(share: [country: 1], seed: seed),
                                  cues: SoundtrackTestSupport.cues(durationS: 90), config: try config())
                .choices.first?.manifest.id
        }
        XCTAssertEqual(try first(7), try first(7))
        XCTAssertNotEqual(try first(0), try first(1), "two trips can get the two takes of one brief")
    }

    func testTheSeedComesFromTheTripIdAndIsStable() {
        // FNV-1a 64 of "abc": a published test vector, so the seed cannot drift
        // between launches or devices the way `hashValue` does.
        XCTAssertEqual(SoundtrackContext.seed(tripId: "abc"), 0xe71f_a219_0541_574b)
    }

    /// §2.5 item 4: a track with no repeatable section cannot fill a film
    /// longer than it, so it is never offered for one.
    func testATrackThatCannotFillTheFilmIsNotOffered() throws {
        let (country, style) = try listed(0)
        let fixed = track("\(style)-depart-fixed", style: style, mood: .depart, repeatable: false)
        let config = try config()
        func offered(_ durationS: Double) -> Bool {
            SoundtrackPicker.rank(catalog: [fixed], context: context(share: [country: 1], durationS: durationS),
                                  cues: SoundtrackTestSupport.cues(durationS: durationS), config: config)
                .choices.contains { $0.manifest.id == fixed.id }
        }
        XCTAssertTrue(offered(60))
        XCTAssertFalse(offered(fixed.durationS + 60))
    }

    func testAStyleWithNoTrackFallsBackAndSaysSo() throws {
        let config = try config()
        let (country, _) = try listed(0)
        let ranking = SoundtrackPicker.rank(
            catalog: catalog(style: config.unlistedStyle), context: context(share: [country: 1]),
            cues: SoundtrackTestSupport.cues(durationS: 90), config: config
        )
        XCTAssertTrue(ranking.styleFellBack)
        XCTAssertTrue(ranking.choices.allSatisfy { $0.manifest.style == config.unlistedStyle })
    }

    // MARK: - The basis a film keeps

    func testTheBasisRoundTripsWithNoPlaceInIt() throws {
        let basis = FilmSoundtrackBasis(cues: SoundtrackTestSupport.cues(durationS: 60), ranking: ["a", "b"])
        let data = try JSONEncoder().encode(basis)
        XCTAssertEqual(try JSONDecoder().decode(FilmSoundtrackBasis.self, from: data), basis)
        let keys = Set((try JSONSerialization.jsonObject(with: data) as? [String: Any])?.keys.map { $0 } ?? [])
        XCTAssertEqual(keys, ["cues", "ranking"])
    }
}
