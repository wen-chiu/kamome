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
/// here on the same trip, after starring and leaving photographs out.
@MainActor
final class FilmPhotoChoicesTests: XCTestCase {
    /// Ten stops, 30 photographs down to 12 so they rank in trip order, imported
    /// through the real pipeline.
    private func importedTrip(
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
    private func filmDecks(
        _ detail: TripRepository.TripDetail, config: TrackingConfig
    ) throws -> [[String]] {
        // The export's own path (`RecapExportJob.compose`): the film ends at the
        // destination, then legs, then the trip.
        let inputs = RecapComposer.photoInputs(detail: detail)
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
}
