@testable import Kamome
import KamomePersistence
import XCTest

/// **Home says the next step while 旅程 is short, and marks a trip with a film**
/// (#295 items 1–2, ADR 2026-10-26-home-shows-a-newcomer-the-next-step; Chiu's
/// review 2026-10-27: the step is a card that opens the trip's film sheet).
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
        let coast = try XCTUnwrap(repository.allTrips().first)
        XCTAssertEqual(HomeNextStep.load(trips: try repository.allTrips(), repository: repository), .makeFilm(coast))

        try repository.saveFilm(film("first", tripId: tripId))
        XCTAssertEqual(
            HomeNextStep.load(trips: try repository.allTrips(), repository: repository), .findJourneys,
            "every trip has its film: the next step is more journeys"
        )

        let hillsId = try repository.saveCompletedTrip(
            title: "Hills", startedAt: 2_000, endedAt: 3_000, segments: [], stops: []
        )
        let hills = try XCTUnwrap(repository.allTrips().first { $0.id == hillsId })
        XCTAssertEqual(
            HomeNextStep.load(trips: try repository.allTrips(), repository: repository), .makeFilm(hills),
            "one trip still without a film is enough, and the card names it"
        )
    }

    /// **Which trip the film card offers** (Chiu 2026-10-27: 「挑最近一趟」): of
    /// the finished trips without a film, the one that began last — not the
    /// list's first, not one with a film, not one still recording.
    func testTheFilmCardOffersTheNewestFinishedTripWithoutAFilm() throws {
        let repository = try repository()
        let older = try repository.saveCompletedTrip(title: "Older", startedAt: 0, endedAt: 1_000, segments: [], stops: [])
        let newer = try repository.saveCompletedTrip(
            title: "Newer", startedAt: 5_000, endedAt: 6_000, segments: [], stops: []
        )
        let filmed = try repository.saveCompletedTrip(
            title: "Filmed", startedAt: 9_000, endedAt: 10_000, segments: [], stops: []
        )
        try repository.saveFilm(film("made", tripId: filmed))
        let recording = TripRecord(id: "live", title: "Now", startedAt: 20_000, endedAt: nil, status: "recording")

        // Oldest first, so "the list's first" and "the newest" disagree.
        let trips = try repository.allTrips().sorted { $0.startedAt < $1.startedAt } + [recording]
        guard case let .makeFilm(offered) = HomeNextStep.load(trips: trips, repository: repository) else {
            return XCTFail("two finished trips have no film: the card offers one")
        }
        XCTAssertEqual(offered.id, newer, "the newest finished trip without a film")
        XCTAssertNotEqual(offered.id, older)

        try repository.saveFilm(film("newer-film", tripId: newer))
        guard case let .makeFilm(next) = HomeNextStep.load(trips: trips, repository: repository) else {
            return XCTFail("the older trip still has no film")
        }
        XCTAssertEqual(next.id, older, "once the newer has its film, the card moves to the next one back")
    }

    func testTheFilmCardNamesTheTripAsItsRowDoes() throws {
        let trip = TripRecord(id: "t", title: "Coast road", startedAt: 0, endedAt: 1_000, status: "completed")
        let text = HomeNextStepRow.filmCardText(for: trip)
        XCTAssertTrue(text.contains(HomeTripRow.headline(for: trip).title), "the row's own title: \(text)")
    }

    func testATripStillRecordingIsNotAskedForAFilm() throws {
        let recording = TripRecord(id: "live", title: "Now", startedAt: 0, endedAt: nil, status: "recording")
        XCTAssertEqual(
            HomeNextStep.load(trips: [recording], repository: try repository()), .findJourneys,
            "Trip Detail's film button waits for the trip to end"
        )
    }

    /// The film mark is a state in the figures' grey, not a control (Chiu
    /// 2026-10-27): the line's last part, so it stacks with the figures (#191).
    func testTheFilmMarkEndsTheFiguresLine() {
        let mark = String(localized: "home_trip_film_made")
        XCTAssertNotEqual(mark, "home_trip_film_made", "the mark has a string")
        let line = HomeTripRow.figuresText(groundM: 172_000, stopCount: 5, filmMade: true)
        XCTAssertTrue(line.hasSuffix(" · " + mark), line)
        XCTAssertFalse(HomeTripRow.figuresText(groundM: 172_000, stopCount: 5).contains(mark))
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
