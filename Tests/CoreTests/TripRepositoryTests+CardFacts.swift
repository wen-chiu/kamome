import KamomePersistence
import KamomeTrackingEngine
import XCTest

/// **A journey card's legs** (#265): the card folds its legs into the gaps
/// between its stops by time, so the facts carry each leg's start and
/// routing verdict — and never its road line, which no card draws.
extension TripRepositoryTests {
    func testJourneyCardFactsCarryTheLegsWithoutTheirGeometry() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let stop = TripRepository.NewStopWithPhotos(
            stop: TripRepository.NewStop(lat: 35.68, lon: 139.65, arrivedAt: 0, departedAt: 600),
            photos: [TripRepository.NewPhoto(assetId: "a")]
        )
        let tripId = try repository.saveImportedTrip(TripRepository.ImportedTrip(
            title: "Legs", startedAt: 0, endedAt: 4_000, source: TripSource.importedPhotos.rawValue,
            segments: [
                TripRepository.NewSegment(mode: "walk", startedAt: 2_000, endedAt: 2_500, points: []),
                TripRepository.NewSegment(mode: "drive", startedAt: 1_000, endedAt: 1_500, points: [])
            ],
            stopsWithPhotos: [stop], routeAttachedPhotos: []
        ))
        let drive = try XCTUnwrap(repository.detail(tripId: tripId)?.segments.first { $0.segment.mode == "drive" })
        try repository.setMatchedPolyline(segmentId: drive.segment.id, encodedPolyline: "_p~iF~ps|U_ulLnnqC")

        let facts = try repository.journeyCardFacts(tripId: tripId)
        XCTAssertEqual(facts.segments.map(\.mode), ["drive", "walk"], "in trip order")
        XCTAssertEqual(facts.segments.map(\.startedAt), [1_000, 2_000])
        XCTAssertEqual(facts.legModes, ["drive", "walk"], "the modes as before")
        XCTAssertTrue(facts.segments.allSatisfy { $0.matchedPolyline == nil }, "the road line is never read")
        XCTAssertEqual(facts.segments.first?.id, drive.segment.id)
    }
}
