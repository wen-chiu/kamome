@testable import Kamome
import KamomePersistence
import XCTest

/// **Home says the next step while 旅程 is short, and marks a trip with a film**
/// (#295 items 1–2, ADR 2026-10-26-home-shows-a-newcomer-the-next-step).
final class HomeNextStepTests: XCTestCase {
    private func repository() throws -> TripRepository {
        TripRepository(database: try AppDatabase.inMemory())
    }

    private func film(_ id: String, tripId: String) -> FilmRecord {
        FilmRecord(
            id: id, tripId: tripId, relativePath: "Films/\(id).mp4",
            format: "mp4", createdAt: 100, appearance: "light", recapMode: "highlight"
        )
    }

    func testOfferedOnlyUnderAShortListThatIsNotEmpty() {
        let maxTrips = AppConfig.loadOrDie().home.nextStepMaxTrips
        XCTAssertGreaterThan(maxTrips, 0, "a threshold of 0 would never offer the line")
        XCTAssertFalse(HomeNextStep.isOffered(tripCount: 0, maxTrips: maxTrips), "the empty state speaks instead")
        XCTAssertTrue(HomeNextStep.isOffered(tripCount: 1, maxTrips: maxTrips), "one trip: the case #295 found")
        XCTAssertTrue(HomeNextStep.isOffered(tripCount: maxTrips, maxTrips: maxTrips))
        XCTAssertFalse(HomeNextStep.isOffered(tripCount: maxTrips + 1, maxTrips: maxTrips))
    }

    func testAFinishedTripWithoutAFilmIsTheNextStepThenMoreJourneys() throws {
        let repository = try repository()
        let tripId = try repository.saveCompletedTrip(
            title: "Coast", startedAt: 0, endedAt: 1_000, segments: [], stops: []
        )
        XCTAssertEqual(HomeNextStep.load(trips: try repository.allTrips(), repository: repository), .makeFilm)

        try repository.saveFilm(film("first", tripId: tripId))
        XCTAssertEqual(
            HomeNextStep.load(trips: try repository.allTrips(), repository: repository), .findJourneys,
            "every trip has its film: the next step is more journeys"
        )

        _ = try repository.saveCompletedTrip(title: "Hills", startedAt: 2_000, endedAt: 3_000, segments: [], stops: [])
        XCTAssertEqual(
            HomeNextStep.load(trips: try repository.allTrips(), repository: repository), .makeFilm,
            "one trip still without a film is enough"
        )
    }

    func testATripStillRecordingIsNotAskedForAFilm() throws {
        let recording = TripRecord(id: "live", title: "Now", startedAt: 0, endedAt: nil, status: "recording")
        XCTAssertEqual(
            HomeNextStep.load(trips: [recording], repository: try repository()), .findJourneys,
            "Trip Detail's film button waits for the trip to end"
        )
    }

    /// The row draws its two lines through a helper that `LocalizationCoverageTests`'
    /// scan cannot see, so they are held here, in both languages, to the glossary's words.
    func testTheNextStepLinesResolveInBothLanguages() throws {
        func value(_ key: String, _ locale: String) throws -> String {
            let path = try XCTUnwrap(Bundle.main.path(forResource: locale, ofType: "lproj"))
            return try XCTUnwrap(Bundle(path: path)).localizedString(forKey: key, value: nil, table: nil)
        }
        XCTAssertEqual(try value("home_next_make_film", "zh-Hant"), "打開一趟旅程，就能製作旅程影片。")
        XCTAssertEqual(try value("home_next_find_journeys", "zh-Hant"), "從照片找出更多旅程")
        for key in ["home_next_make_film", "home_next_find_journeys", "home_trip_has_film"] {
            XCTAssertNotEqual(try value(key, "en"), key, "\(key) has no English string")
        }
    }

    func testARowKnowsItsTripHasAFilm() throws {
        let repository = try repository()
        let tripId = try repository.saveCompletedTrip(
            title: "Coast", startedAt: 0, endedAt: 1_000, segments: [], stops: []
        )
        let trip = try XCTUnwrap(repository.allTrips().first)
        XCTAssertEqual(HomeTripFigures.load(trip: trip, repository: repository)?.hasFilm, false)

        try repository.saveFilm(film("first", tripId: tripId))
        let figures = try XCTUnwrap(HomeTripFigures.load(trip: trip, repository: repository))
        XCTAssertTrue(figures.hasFilm, "the row draws its film mark")
        XCTAssertEqual(figures.filmCount, 1)

        _ = try repository.deleteFilm(filmId: "first")
        XCTAssertEqual(HomeTripFigures.load(trip: trip, repository: repository)?.hasFilm, false, "a deleted film takes its mark")
    }
}
