import KamomePersistence
import KamomeTrackingEngine
import XCTest

final class TripRepositoryTests: XCTestCase {
    /// End-to-end: replay the Perth fixture through the real engine, persist
    /// the result, and read it back — the exact path End Trip takes.
    func testEngineOutputRoundTripsThroughRepository() throws {
        let engine = try GPXReplay.run(fixture: "perth_margaret_river_day1.gpx")
        let database = try AppDatabase.inMemory()
        let repository = TripRepository(database: database)

        let segments = engine.segments.map { segment in
            TripRepository.NewSegment(
                mode: segment.mode.rawValue,
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                points: segment.points.map {
                    TripRepository.NewTrackpoint(ts: $0.ts, lat: $0.lat, lon: $0.lon, hAcc: $0.hAccM)
                }
            )
        }
        let stops = engine.stops.map {
            TripRepository.NewStop(lat: $0.lat, lon: $0.lon, arrivedAt: $0.arrivedAt, departedAt: $0.departedAt)
        }

        let tripId = try repository.saveCompletedTrip(
            title: "Perth Day 1",
            startedAt: engine.segments.first?.startedAt ?? 0,
            endedAt: engine.stops.last?.departedAt ?? 0,
            segments: segments,
            stops: stops
        )

        XCTAssertEqual(try repository.allTrips().count, 1)
        XCTAssertEqual(try repository.allTrips().first?.status, "completed")
        XCTAssertEqual(try repository.stopCount(tripId: tripId), 4)
        XCTAssertEqual(try repository.segmentCount(tripId: tripId), engine.segments.count)
        let pointTotal = engine.segments.reduce(0) { $0 + $1.points.count }
        XCTAssertEqual(try repository.trackpointCount(tripId: tripId), pointTotal)
    }
}
