import Foundation
import KamomePersistence
import XCTest

/// `applyMerge` moves every row a trip owns onto the survivor, in one
/// transaction (ADR 2026-09-24).
final class TripMergeRepositoryTests: XCTestCase {
    private func recordedTrip(_ repository: TripRepository, start: Double, lon: Double) throws -> String {
        try repository.saveCompletedTrip(
            title: "Day",
            startedAt: start, endedAt: start + 3_600,
            segments: [
                TripRepository.NewSegment(mode: "drive", startedAt: start, endedAt: start + 3_000, points: [
                    TripRepository.NewTrackpoint(ts: start, lat: -44, lon: lon),
                    TripRepository.NewTrackpoint(ts: start + 3_000, lat: -44, lon: lon + 0.5)
                ])
            ],
            stops: [TripRepository.NewStop(lat: -44, lon: lon + 0.5, arrivedAt: start + 3_000, departedAt: start + 3_600)]
        )
    }

    func testEverythingMovesToTheSurvivorAndTheAbsorbedTripIsGone() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let first = try recordedTrip(repository, start: 0, lon: 168)
        let second = try recordedTrip(repository, start: 86_400, lon: 169)
        let secondStop = try XCTUnwrap(try repository.detail(tripId: second)?.stops.first)
        try repository.replacePhotoRefs(tripId: second, with: [
            PhotoRefRecord(id: "p1", tripId: second, stopId: secondStop.id, phAssetId: "asset-1", isHighlight: 1)
        ])
        try repository.saveFilm(FilmRecord(
            id: "f1", tripId: second, relativePath: "Films/f1.mp4", format: "mp4",
            createdAt: 1, appearance: "light", recapMode: "highlight"
        ))
        let firstStop = try XCTUnwrap(try repository.detail(tripId: first)?.stops.first)

        try repository.applyMerge(TripRepository.TripMerge(
            keptId: first, absorbedIds: [second],
            startedAt: 0, endedAt: 90_000,
            source: "imported_photos", statsJson: nil, discoveryKey: "journey-key",
            gapSegments: [TripRepository.NewSegment(
                mode: "drive", startedAt: 3_600, endedAt: 86_400,
                points: [
                    TripRepository.NewTrackpoint(ts: 3_600, lat: -44, lon: 168.5),
                    TripRepository.NewTrackpoint(ts: 86_400, lat: -44, lon: 169)
                ],
                source: "merge_gap"
            )],
            junctionStops: [],
            stopDepartures: [(firstStop.id, 86_400)]
        ))

        XCTAssertNil(try repository.detail(tripId: second))
        let merged = try XCTUnwrap(try repository.detail(tripId: first))
        XCTAssertEqual(merged.segments.count, 3)
        XCTAssertEqual(merged.segments.map { $0.segment.source }, [nil, "merge_gap", nil])
        XCTAssertEqual(merged.stops.count, 2)
        XCTAssertEqual(merged.stops.first?.departedAt, 86_400)
        XCTAssertEqual(merged.photos.map(\.stopId), [secondStop.id], "a photo keeps its stop")
        XCTAssertEqual(merged.photos.first?.isHighlight, 1)
        XCTAssertEqual(try repository.films(tripId: first).map(\.id), ["f1"], "films of the parts are kept")
        XCTAssertEqual(merged.trip.endedAt, 90_000)
        XCTAssertEqual(merged.trip.source, "imported_photos")
        XCTAssertEqual(merged.trip.discoveryKey, "journey-key")
        XCTAssertEqual(try repository.allTrips().count, 1)
    }

    /// A merge naming a trip that is not there changes nothing at all.
    func testAMissingTripRollsTheWholeMergeBack() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let first = try recordedTrip(repository, start: 0, lon: 168)
        let second = try recordedTrip(repository, start: 86_400, lon: 169)

        XCTAssertThrowsError(try repository.applyMerge(TripRepository.TripMerge(
            keptId: first, absorbedIds: [second, "no-such-trip"],
            startedAt: 0, endedAt: 90_000, source: "recorded", statsJson: nil, discoveryKey: nil,
            gapSegments: [], junctionStops: [], stopDepartures: []
        )))
        XCTAssertEqual(try repository.allTrips().count, 2)
        XCTAssertEqual(try repository.segmentCount(tripId: second), 1)
    }
}
