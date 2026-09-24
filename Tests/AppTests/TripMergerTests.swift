@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomePersistence
import KamomeTripComposer
import XCTest

/// Chiu's three calls on trip merge (ADR 2026-09-24 (b)): a recording may merge
/// with a photo reconstruction and the whole is then marked reconstructed; the
/// gap between parts is an inferred leg, never a recorded one; films are kept.
/// Positions are synthetic.
final class TripMergerTests: XCTestCase {
    private let config = AppConfig.loadOrDie()
    private let day = 86_400.0

    /// A day's drive east along -44°, ending at a stop, with measured stats.
    private func recordedDay(
        _ repository: TripRepository, start: Double, fromLon: Double, toLon: Double
    ) throws -> String {
        let end = start + 8 * 3_600
        let id = try repository.saveCompletedTrip(
            title: "Day",
            startedAt: start, endedAt: end,
            segments: [
                TripRepository.NewSegment(mode: "walk", startedAt: start, endedAt: start + 300, points: [
                    TripRepository.NewTrackpoint(ts: start, lat: -44, lon: fromLon),
                    TripRepository.NewTrackpoint(ts: start + 300, lat: -44, lon: fromLon + 0.001)
                ]),
                TripRepository.NewSegment(mode: "drive", startedAt: start + 300, endedAt: end - 3_600, points: [
                    TripRepository.NewTrackpoint(ts: start + 300, lat: -44, lon: fromLon + 0.001),
                    TripRepository.NewTrackpoint(ts: end - 3_600, lat: -44, lon: toLon)
                ])
            ],
            stops: [TripRepository.NewStop(lat: -44, lon: toLon, arrivedAt: end - 3_600, departedAt: end)]
        )
        let stats = TripStats(distanceM: 100_000, driveS: 20_000, walkS: 300, stopCount: 1, topSpeedKmh: 95)
        try repository.updateTripStats(tripId: id, statsJson: try XCTUnwrap(stats.jsonString()))
        return id
    }

    private func importedDay(_ repository: TripRepository, start: Double, fromLon: Double, toLon: Double) throws -> String {
        try repository.saveImportedTrip(TripRepository.ImportedTrip(
            title: "Photos", startedAt: start, endedAt: start + 6 * 3_600,
            source: TripSource.importedPhotos.rawValue,
            segments: [TripRepository.NewSegment(
                mode: "drive", startedAt: start, endedAt: start + 6 * 3_600,
                points: [
                    TripRepository.NewTrackpoint(ts: start, lat: -44, lon: fromLon),
                    TripRepository.NewTrackpoint(ts: start + 6 * 3_600, lat: -44, lon: toLon)
                ],
                source: SegmentSource.exif.rawValue
            )],
            stopsWithPhotos: [], routeAttachedPhotos: [], discoveryKey: "photos-journey"
        ))
    }

    private func details(_ repository: TripRepository, _ ids: [String]) throws -> [TripRepository.TripDetail] {
        try ids.map { try XCTUnwrap(try repository.detail(tripId: $0)) }
    }

    /// Two recorded days, ending and beginning at the same hotel: no gap leg,
    /// the first day's last stop covers the night, measured totals add up.
    func testTwoRecordedDaysAtOneHotelBecomeOneRecordedTrip() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let first = try recordedDay(repository, start: 0, fromLon: 168, toLon: 169)
        let second = try recordedDay(repository, start: day, fromLon: 169.0005, toLon: 170)

        let merge = try TripMerger.plan(parts: try details(repository, [second, first]), config: config)
        XCTAssertEqual(merge.keptId, first, "the earliest trip survives, whatever order they were picked in")
        XCTAssertEqual(merge.absorbedIds, [second])
        XCTAssertTrue(merge.gapSegments.isEmpty)
        XCTAssertTrue(merge.junctionStops.isEmpty)
        XCTAssertEqual(merge.stopDepartures.count, 1)
        XCTAssertEqual(merge.stopDepartures.first?.departedAt, day, "the stop lasts until the next day starts")
        XCTAssertEqual(merge.source, TripSource.recorded.rawValue)
        let stats = try XCTUnwrap(TripStats.from(jsonString: merge.statsJson))
        XCTAssertEqual(stats.distanceM, 200_000)
        XCTAssertEqual(stats.stopCount, 2)
        XCTAssertEqual(stats.topSpeedKmh, 95)

        try repository.applyMerge(merge)
        let merged = try XCTUnwrap(try repository.detail(tripId: first))
        XCTAssertEqual(merged.trip.endedAt, day + 8 * 3_600)
        XCTAssertEqual(merged.stops.count, 2)
    }

    /// A recorded day and a photo-rebuilt day far apart: the stretch between is
    /// a gap leg that draws as inferred, and the whole trip is reconstructed.
    func testARecordingAndAReconstructionFarApartAreJoinedByAnInferredLeg() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let recorded = try recordedDay(repository, start: 0, fromLon: 168, toLon: 169)
        let rebuilt = try importedDay(repository, start: 2 * day, fromLon: 171, toLon: 172)

        let merge = try TripMerger.plan(parts: try details(repository, [recorded, rebuilt]), config: config)
        XCTAssertEqual(merge.source, TripSource.importedPhotos.rawValue, "any reconstructed part marks the whole")
        XCTAssertNil(merge.statsJson, "reconstructed days have no measured total")
        XCTAssertEqual(merge.discoveryKey, "photos-journey")
        let gap = try XCTUnwrap(merge.gapSegments.first)
        XCTAssertEqual(merge.gapSegments.count, 1)
        XCTAssertEqual(gap.mode, "drive", "the gap is the vehicle's, not the walk before it")
        XCTAssertEqual(gap.points.map(\.lon), [169, 171])
        XCTAssertEqual(gap.startedAt, 8 * 3_600)
        XCTAssertEqual(gap.endedAt, 2 * day)

        try repository.applyMerge(merge)
        let merged = try XCTUnwrap(try repository.detail(tripId: recorded))
        XCTAssertEqual(merged.trip.tripSource, .importedPhotos)
        let provenances = merged.segments.map { RecapComposer.provenance(for: $0.segment) }
        XCTAssertEqual(provenances, [.recorded, .recorded, .inferred, .inferred],
                       "the recording stays recorded; the gap and the photos stay inferred")
    }

    func testOverlappingTripsAreRefused() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let first = try recordedDay(repository, start: 0, fromLon: 168, toLon: 169)
        let overlapping = try importedDay(repository, start: 3_600, fromLon: 168, toLon: 169)
        XCTAssertThrowsError(try TripMerger.plan(parts: try details(repository, [first, overlapping]), config: config)) {
            XCTAssertEqual($0 as? TripMerger.Refusal, .overlapping)
        }
    }

    func testOneTripIsNotAMerge() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let only = try recordedDay(repository, start: 0, fromLon: 168, toLon: 169)
        XCTAssertThrowsError(try TripMerger.plan(parts: try details(repository, [only]), config: config)) {
            XCTAssertEqual($0 as? TripMerger.Refusal, .tooFew)
        }
    }
}
