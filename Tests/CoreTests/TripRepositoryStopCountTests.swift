import KamomePersistence
import KamomeTripComposer
import XCTest

final class TripRepositoryStopCountTests: XCTestCase {
    /// Home's row and Trip Detail's strip read the stop count from `stats_json`,
    /// written once at completion. Deleting or merging a stop must move it, and
    /// only it (#211).
    func testDeleteAndMergeKeepTheStoredStopCountTrue() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let tripId = try repository.saveCompletedTrip(
            title: "Count fixture", startedAt: 0, endedAt: 10_000, segments: [],
            stops: (0..<4).map {
                TripRepository.NewStop(
                    lat: -32.0 + Double($0) * 0.01, lon: 115.87,
                    arrivedAt: Double($0) * 1_000, departedAt: Double($0) * 1_000 + 500
                )
            }
        )
        let stats = TripStats(distanceM: 271_000, driveS: 9_000, walkS: 0, stopCount: 4, topSpeedKmh: 96)
        try repository.updateTripStats(tripId: tripId, statsJson: try XCTUnwrap(
            String(data: JSONEncoder().encode(stats), encoding: .utf8)
        ))
        func stored() throws -> TripStats {
            let json = try XCTUnwrap(try repository.detail(tripId: tripId)?.trip.statsJson)
            return try JSONDecoder().decode(TripStats.self, from: Data(json.utf8))
        }
        var stops = try XCTUnwrap(try repository.detail(tripId: tripId)).stops

        try repository.deleteStop(stopId: stops[3].id)
        XCTAssertEqual(try stored().stopCount, 3, "a deleted stop leaves the count")
        XCTAssertEqual(try repository.stopCount(tripId: tripId), 3)

        stops = try XCTUnwrap(try repository.detail(tripId: tripId)).stops
        try repository.mergeStops(keptId: stops[0].id, absorbedId: stops[1].id)
        let after = try stored()
        XCTAssertEqual(after.stopCount, 2, "a merged stop leaves the count")
        XCTAssertEqual(after, TripStats(distanceM: 271_000, driveS: 9_000, walkS: 0, stopCount: 2, topSpeedKmh: 96),
                       "distance, times and top speed stay as recorded")
    }

    /// An imported trip has no stats, and a stats column that is not JSON must
    /// not make a delete fail: the edit goes through and the column is left as it was.
    func testDeleteLeavesAbsentOrUnreadableStatsAlone() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        func trip(_ title: String) throws -> String {
            try repository.saveCompletedTrip(
                title: title, startedAt: 0, endedAt: 10_000, segments: [],
                stops: [
                    TripRepository.NewStop(lat: -32.0, lon: 115.87, arrivedAt: 1_000, departedAt: 2_000),
                    TripRepository.NewStop(lat: -32.1, lon: 115.87, arrivedAt: 3_000, departedAt: 4_000)
                ]
            )
        }
        let noStats = try trip("none")
        try repository.deleteStop(stopId: try XCTUnwrap(try repository.detail(tripId: noStats)).stops[0].id)
        XCTAssertNil(try repository.detail(tripId: noStats)?.trip.statsJson)
        XCTAssertEqual(try repository.stopCount(tripId: noStats), 1)

        let broken = try trip("broken")
        try repository.updateTripStats(tripId: broken, statsJson: "not json")
        try repository.deleteStop(stopId: try XCTUnwrap(try repository.detail(tripId: broken)).stops[0].id)
        XCTAssertEqual(try repository.detail(tripId: broken)?.trip.statsJson, "not json")
        XCTAssertEqual(try repository.stopCount(tripId: broken), 1)
    }
}
