@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import XCTest

/// **What the photo picker promises is what the film shows** (ADR 2026-09-24).
///
/// The picker numbers the photographs a stop's deck will use. If that number
/// came from anywhere but the export's own selection, the screen would be a
/// second opinion about the film — the way the Stop Editor's star used to look
/// like it did something while the film ignored it. So the preview
/// (`RecapComposer.filmDecks`) and the film (`RecapComposer.trip`) are compared
/// here on the same trip, after starring, picking and leaving photographs out,
/// and after putting stops in and taking them out (Chiu 2026-09-25).
@MainActor
final class FilmPhotoChoicesTests: XCTestCase {
    /// Ten stops, 30 photographs down to 12 so they rank in trip order, imported
    /// through the real pipeline.
    func importedTrip(
        config: TrackingConfig
    ) async throws -> (TripRepository, TripRepository.TripDetail) {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let service = ImportService(repository: repository, config: config)
        var photos: [ImportPhoto] = []
        for stop in 0..<10 {
            let base = Double(stop) * (config.photoImport.stopSplitGapS + 3_600)
            for photo in 0..<(30 - stop * 2) {
                photos.append(ImportPhoto(
                    assetId: "s\(stop)-p\(photo)", timestamp: base + Double(photo) * 60,
                    lat: 64.0 + Double(stop) * 0.2, lon: -20.0
                ))
            }
        }
        let tripId = try await service.importTrip(title: "choices", photos: photos)
        return (repository, try XCTUnwrap(try repository.detail(tripId: tripId)))
    }

    /// The film as the export composes it, as asset ids per presented stop.
    func filmDecks(
        _ detail: TripRepository.TripDetail, config: TrackingConfig
    ) throws -> [[String]] {
        // The export's own path (`RecapExportJob.compose`): the film ends at the
        // destination, then legs, then the trip.
        let inputs = RecapComposer.photoInputs(detail: detail, analysis: config.photoAnalysis)
        let film = RecapComposer.filmRecords(
            segments: detail.segments, stops: detail.stops,
            epsilonM: config.simplify.epsilonM, matchedEpsilonM: config.matching.displayEpsilonM,
            homeRadiusM: config.discovery.awayRadiusM
        )
        let legs = RecapComposer.legs(
            from: film.segments, epsilonM: config.simplify.epsilonM,
            matchedEpsilonM: config.matching.displayEpsilonM
        )
        let recap = try XCTUnwrap(RecapComposer.trip(
            trip: detail.trip, legs: legs, stops: film.stops, stats: nil,
            photosByStop: inputs.byStop,
            rawPhotoCounts: inputs.rawCounts, favoriteCounts: inputs.starredCounts,
            highlightedAssets: inputs.highlighted,
            pickedAssets: inputs.picked, pickedCounts: inputs.pickedCounts,
            analysis: inputs.analysis,
            highlightMaxPhotos: config.photoImport.deckHighlightMaxPhotos,
            weighting: config.export
        ))
        return recap.stops.map { stop in
            stop.photos.compactMap { ref in
                if case let .asset(id) = ref { return id }
                return nil
            }
        }
    }

    func testThePreviewIsTheFilmsOwnSelection() async throws {
        let config = AppConfig.loadOrDie()
        let (repository, imported) = try await importedTrip(config: config)
        let choices = FilmPhotoChoices(tripId: imported.trip.id, config: config, repository: repository)

        // The quietest stop is not in the film until one of its photographs is
        // starred; a busy stop loses a photograph the app had picked.
        let quiet = try XCTUnwrap(imported.stops.last)
        XCTAssertFalse(choices.isInFilm(stopId: quiet.id), "10 stops earn 8: the quietest is out")
        let busy = try XCTUnwrap(imported.stops.first)
        let picked = try XCTUnwrap(choices.filmDeck(for: busy.id).first)
        let pickedPhoto = try XCTUnwrap(choices.photos(for: busy.id).first { $0.phAssetId == picked })
        choices.setChoice(.excluded, photo: pickedPhoto)
        let starred = try XCTUnwrap(choices.photos(for: quiet.id).last)
        choices.setChoice(.starred, photo: starred)

        XCTAssertTrue(choices.isInFilm(stopId: quiet.id), "a starred stop is always presented")
        XCTAssertEqual(choices.filmDeck(for: quiet.id).first, starred.phAssetId, "the star leads its deck")
        XCTAssertFalse(choices.filmDeck(for: busy.id).contains(picked), "a left-out photograph never returns")

        // And the export, composed from the same records, agrees stop for stop.
        let detail = try XCTUnwrap(try repository.detail(tripId: imported.trip.id))
        let preview = detail.stops.compactMap { choices.decks[$0.id] }
        XCTAssertEqual(preview, try filmDecks(detail, config: config))
    }

    /// Leaving a photograph out takes it off its stop's count too: a stop whose
    /// every photograph is left out cannot outrank one that still has some.
    func testLeftOutPhotographsDoNotCountTowardsTheirStop() async throws {
        let config = AppConfig.loadOrDie()
        let (repository, imported) = try await importedTrip(config: config)
        let stop = try XCTUnwrap(imported.stops.first)
        for photo in imported.photos where photo.stopId == stop.id {
            try repository.setPhotoFilmChoice(photoId: photo.id, choice: .excluded)
        }
        let detail = try XCTUnwrap(try repository.detail(tripId: imported.trip.id))
        let inputs = RecapComposer.photoInputs(detail: detail)
        XCTAssertNil(inputs.byStop[stop.id])
        XCTAssertNil(inputs.rawCounts[stop.id])
    }

    /// The preview after an edit, checked against the export composed from the
    /// same records.
    private func assertPreviewIsTheFilm(
        _ choices: FilmPhotoChoices, _ repository: TripRepository, config: TrackingConfig,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let detail = try XCTUnwrap(try repository.detail(tripId: choices.tripId))
        let preview = detail.stops.compactMap { choices.decks[$0.id] }
        XCTAssertEqual(preview, try filmDecks(detail, config: config), file: file, line: line)
    }

    /// **What is numbered is what plays** (Chiu 2026-09-25): a tap takes a
    /// numbered photograph out and puts any other in, from 1 to the cap, and the
    /// app never tops a picked deck back up.
    func testAPickedDeckIsExactlyThePicksFromOneToTheCap() async throws {
        let config = AppConfig.loadOrDie()
        let (repository, imported) = try await importedTrip(config: config)
        let choices = FilmPhotoChoices(tripId: imported.trip.id, config: config, repository: repository)
        let stop = try XCTUnwrap(imported.stops.first)
        let auto = choices.filmDeck(for: stop.id)
        XCTAssertEqual(auto.count, config.export.tierStandardPhotos, "precondition: the app's deck")
        XCTAssertFalse(choices.isPicked(stopId: stop.id))

        func photo(_ assetId: String) throws -> PhotoRefRecord {
            try XCTUnwrap(choices.photos(for: stop.id).first { $0.phAssetId == assetId })
        }

        // Down to one: the untouched photographs keep their places.
        XCTAssertEqual(choices.toggle(try photo(auto[0]), stopId: stop.id), .changed)
        XCTAssertTrue(choices.isPicked(stopId: stop.id))
        XCTAssertEqual(choices.filmDeck(for: stop.id), Array(auto.dropFirst()))
        XCTAssertEqual(choices.toggle(try photo(auto[1]), stopId: stop.id), .changed)
        XCTAssertEqual(choices.filmDeck(for: stop.id), [auto[2]], "one photograph is a deck")
        try assertPreviewIsTheFilm(choices, repository, config: config)

        // The last one is not removed without asking.
        XCTAssertEqual(choices.toggle(try photo(auto[2]), stopId: stop.id), .wouldEmptyStop)
        XCTAssertEqual(choices.filmDeck(for: stop.id), [auto[2]])

        // Up to the cap, and no further.
        let unpicked = choices.photos(for: stop.id).filter { !auto.contains($0.phAssetId) }
        for extra in unpicked.prefix(choices.maxPhotos - 1) {
            XCTAssertEqual(choices.toggle(extra, stopId: stop.id), .changed)
        }
        XCTAssertEqual(choices.filmDeck(for: stop.id).count, choices.maxPhotos)
        let overflow = try XCTUnwrap(unpicked.dropFirst(choices.maxPhotos - 1).first)
        XCTAssertEqual(choices.toggle(overflow, stopId: stop.id), .full)
        XCTAssertEqual(choices.filmDeck(for: stop.id).count, choices.maxPhotos)
        try assertPreviewIsTheFilm(choices, repository, config: config)

        // "Automatic" hands it back.
        choices.resetToAuto(stopId: stop.id)
        XCTAssertFalse(choices.isPicked(stopId: stop.id))
        XCTAssertEqual(choices.filmDeck(for: stop.id), auto)
    }

    /// **The person's word lands on top of the app's** (Chiu 2026-09-25). A
    /// stop put in joins and the film grows; a stop taken out leaves and nothing
    /// takes its place; picking photographs never moves another stop.
    func testPuttingStopsInAndTakingThemOutMovesNoOtherStop() async throws {
        let config = AppConfig.loadOrDie()
        let (repository, imported) = try await importedTrip(config: config)
        let choices = FilmPhotoChoices(tripId: imported.trip.id, config: config, repository: repository)
        let before = choices.filmStops.map(\.id)
        let quiet = try XCTUnwrap(imported.stops.last)
        XCTAssertFalse(before.contains(quiet.id), "precondition: 10 stops earn 8")
        XCTAssertTrue(choices.otherStops.map(\.id).contains(quiet.id), "a stop left out is offered")

        choices.putIn(stopId: quiet.id)
        XCTAssertEqual(Set(choices.filmStops.map(\.id)), Set(before + [quiet.id]), "the film grows by one")
        XCTAssertFalse(choices.otherStops.map(\.id).contains(quiet.id))
        try assertPreviewIsTheFilm(choices, repository, config: config)

        let busy = try XCTUnwrap(imported.stops.first)
        choices.takeOut(stopId: busy.id)
        XCTAssertEqual(Set(choices.filmStops.map(\.id)), Set(before + [quiet.id]).subtracting([busy.id]),
                       "nothing takes a taken-out stop's place")
        XCTAssertTrue(choices.isTakenOut(stopId: busy.id))
        XCTAssertTrue(choices.otherStops.map(\.id).contains(busy.id), "a taken-out stop can be put back")
        try assertPreviewIsTheFilm(choices, repository, config: config)

        // Picking at a film stop changes that stop's deck and nothing else.
        let second = try XCTUnwrap(choices.filmStops.first)
        let stopsBefore = choices.filmStops.map(\.id)
        let deck = choices.filmDeck(for: second.id)
        let first = try XCTUnwrap(choices.photos(for: second.id).first { deck.contains($0.phAssetId) })
        XCTAssertEqual(choices.toggle(first, stopId: second.id), .changed)
        XCTAssertEqual(choices.filmStops.map(\.id), stopsBefore)
    }

    /// **"N stops · M photos" above Export counts the film** (Chiu 2026-09-26):
    /// M is every deck of every stop the film presents, and it moves with them.
    func testThePhotoCountIsTheFilmsDecksAndFollowsAStopOut() async throws {
        let config = AppConfig.loadOrDie()
        let (repository, imported) = try await importedTrip(config: config)
        let choices = FilmPhotoChoices(tripId: imported.trip.id, config: config, repository: repository)
        let total = choices.filmStops.reduce(0) { $0 + choices.filmDeck(for: $1.id).count }
        XCTAssertGreaterThan(total, 0, "precondition: the fixture's film has photographs")
        XCTAssertEqual(choices.filmPhotoCount, total)

        let stop = try XCTUnwrap(choices.filmStops.first { !choices.filmDeck(for: $0.id).isEmpty })
        let itsDeck = choices.filmDeck(for: stop.id).count
        choices.takeOut(stopId: stop.id)
        XCTAssertEqual(choices.filmPhotoCount, total - itsDeck, "a stop taken out takes its photographs with it")
    }

    /// A tap on a photograph at a stop the film does not present puts the stop
    /// in with that one photograph — even a stop the person took out.
    func testTappingAPhotoAtAStopOutOfTheFilmPutsItIn() async throws {
        let config = AppConfig.loadOrDie()
        let (repository, imported) = try await importedTrip(config: config)
        let choices = FilmPhotoChoices(tripId: imported.trip.id, config: config, repository: repository)
        let stop = try XCTUnwrap(imported.stops.first)
        choices.takeOut(stopId: stop.id)
        XCTAssertFalse(choices.isInFilm(stopId: stop.id))

        let photo = try XCTUnwrap(choices.photos(for: stop.id).last)
        XCTAssertEqual(choices.toggle(photo, stopId: stop.id), .changed)
        XCTAssertTrue(choices.isInFilm(stopId: stop.id))
        XCTAssertFalse(choices.isTakenOut(stopId: stop.id))
        XCTAssertEqual(choices.filmDeck(for: stop.id), [photo.phAssetId])
        try assertPreviewIsTheFilm(choices, repository, config: config)
    }

    /// Never-use and a pick cannot hold together: each clears the other.
    func testLeavingAPickedPhotographOutUnpicksIt() async throws {
        let config = AppConfig.loadOrDie()
        let (repository, imported) = try await importedTrip(config: config)
        let stop = try XCTUnwrap(imported.stops.first)
        let photos = imported.photos.filter { $0.stopId == stop.id }
        try repository.setPhotoFilmChoice(photoId: photos[0].id, choice: .excluded)
        try repository.setStopPicks(stopId: stop.id, photoIds: [photos[0].id, photos[1].id])
        func record(_ id: String) throws -> PhotoRefRecord {
            try XCTUnwrap(try repository.detail(tripId: imported.trip.id)?.photos.first { $0.id == id })
        }
        XCTAssertEqual(try record(photos[0].id).isExcluded, 0, "picking a left-out photograph lets it back")
        XCTAssertEqual(try record(photos[0].id).filmPick, 1)
        try repository.setPhotoFilmChoice(photoId: photos[1].id, choice: .excluded)
        XCTAssertEqual(try record(photos[1].id).filmPick, 0, "leaving one out unpicks it")
    }
}
