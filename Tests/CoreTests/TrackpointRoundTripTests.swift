import KamomePersistence
import XCTest

/// Phase 0 gate (spec §7): insert + read back 50,000 trackpoints against an
/// in-memory database in under 2 seconds.
final class TrackpointRoundTripTests: XCTestCase {
    private static let pointCount = 50_000

    func testFiftyThousandTrackpointsRoundTripUnderTwoSeconds() throws {
        let database = try AppDatabase.inMemory()

        let trip = TripRecord(id: "trip-1", title: "Perf fixture", startedAt: 0, status: "completed")
        let segment = SegmentRecord(id: "seg-1", tripId: trip.id, mode: "drive", startedAt: 0)
        try database.writer.write { db in
            try trip.insert(db)
            try segment.insert(db)
        }

        let start = Date()

        try database.writer.write { db in
            for index in 0..<Self.pointCount {
                var point = TrackpointRecord(
                    segmentId: segment.id,
                    ts: Double(index),
                    lat: -31.95 + Double(index) * 1e-5,
                    lon: 115.86 + Double(index) * 1e-5,
                    hAcc: 5,
                    speed: 25,
                    course: 180,
                    altitude: 10
                )
                try point.insert(db)
            }
        }

        let fetched = try database.writer.read { db in
            try TrackpointRecord
                .filter(sql: "segment_id = ?", arguments: [segment.id])
                .order(sql: "ts")
                .fetchAll(db)
        }

        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(fetched.count, Self.pointCount)
        XCTAssertEqual(fetched.first?.ts, 0)
        XCTAssertEqual(fetched.last?.ts, Double(Self.pointCount - 1))
        XCTAssertEqual(fetched[1].lat, -31.95 + 1e-5, accuracy: 1e-9)
        XCTAssertLessThan(elapsed, 2.0, "round trip took \(elapsed)s, gate is < 2s")
    }
}
