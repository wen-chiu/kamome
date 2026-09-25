@testable import Kamome
import KamomeConfig
import KamomePersistence
import XCTest

/// **The analysed pick reaches the film the way the time-based one did**
/// (ADR 2026-09-25 (c)): all at once, never stop by stop, and the export sheet
/// still shows exactly what the export plays.
extension FilmPhotoChoicesTests {
    /// Stop 0's thirty photographs are one burst; every other photograph is
    /// its own view. `leaving` photographs get no row.
    private func analyse(
        _ detail: TripRepository.TripDetail, repository: TripRepository,
        utilityAt stopId: String? = nil, leaving skipped: Set<String> = []
    ) throws {
        let burst = try XCTUnwrap(detail.stops.first).id
        for (index, photo) in detail.photos.enumerated() where photo.stopId != nil && !skipped.contains(photo.phAssetId) {
            let axis = photo.stopId == burst ? 0 : index + 1
            let print: [Float] = (0...detail.photos.count).map { $0 == axis ? 1 : 0 }
            try repository.savePhotoAnalysis(PhotoAnalysisRecord(
                phAssetId: photo.phAssetId, version: PhotoAnalysisVersion.current, outcome: .analyzed,
                isUtility: photo.stopId == stopId ? 1 : 0, quality: nil,
                featurePrint: PhotoAnalysisRecord.encode(featurePrint: print), analyzedAt: 0
            ))
        }
    }

    func testTheAnalysedPickArrivesOnceEveryStopPhotographHasARow() async throws {
        let config = AppConfig.loadOrDie()
        let (repository, imported) = try await importedTrip(config: config)
        let burst = try XCTUnwrap(imported.stops.first).id
        let timeBased = RecapComposer.filmPlan(detail: imported, config: config, useAnalysis: false).decks
        XCTAssertEqual(timeBased[burst]?.count, config.export.tierStandardPhotos, "precondition")

        // One photograph still waiting: the whole trip plays as before.
        let waiting = try XCTUnwrap(imported.photos.last { $0.stopId != nil }).phAssetId
        try analyse(imported, repository: repository, leaving: [waiting])
        var detail = try XCTUnwrap(try repository.detail(tripId: imported.trip.id))
        XCTAssertNil(RecapComposer.photoInputs(detail: detail, analysis: config.photoAnalysis).analysis)
        XCTAssertEqual(RecapComposer.filmPlan(detail: detail, config: config).decks, timeBased)

        // The last row lands: the burst is one photograph, and the sheet agrees
        // with the export.
        try analyse(imported, repository: repository)
        detail = try XCTUnwrap(try repository.detail(tripId: imported.trip.id))
        let analysed = RecapComposer.filmPlan(detail: detail, config: config).decks
        XCTAssertEqual(analysed[burst]?.count, 1, "thirty frames of one view are one moment")
        let choices = FilmPhotoChoices(tripId: imported.trip.id, config: config, repository: repository)
        XCTAssertEqual(detail.stops.compactMap { choices.decks[$0.id] }, try filmDecks(detail, config: config))
    }

    /// A stop whose photographs are all receipts earns nothing by them.
    func testUtilityPhotographsDoNotEarnTheirStopAPlace() async throws {
        let config = AppConfig.loadOrDie()
        let (repository, imported) = try await importedTrip(config: config)
        let busiest = try XCTUnwrap(imported.stops.first).id
        XCTAssertNotNil(RecapComposer.filmPlan(detail: imported, config: config).decks[busiest], "precondition")

        try analyse(imported, repository: repository, utilityAt: busiest)
        let detail = try XCTUnwrap(try repository.detail(tripId: imported.trip.id))
        XCTAssertEqual(RecapComposer.photoInputs(detail: detail, analysis: config.photoAnalysis).rawCounts[busiest], 0)
        XCTAssertNil(RecapComposer.filmPlan(detail: detail, config: config).decks[busiest])
    }
}
