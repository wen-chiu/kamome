import GRDB
import XCTest

@testable import KamomePersistence

final class SchemaTests: XCTestCase {
    func testMigrationToV1CreatesAllTablesAndIndex() throws {
        let database = try AppDatabase.inMemory()

        let tables = try database.writer.read { db in
            try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        let expected: Set<String> = ["trip", "segment", "trackpoint", "stop", "photo_ref", "plan", "plan_stop"]
        XCTAssertTrue(expected.isSubset(of: tables), "missing tables: \(expected.subtracting(tables))")

        let indexes = try database.writer.read { db in
            try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'")
        }
        XCTAssertTrue(indexes.contains("idx_trackpoint_segment_ts"))
    }

    func testMigrationsAreForwardOnlyAndComplete() throws {
        let queue = try DatabaseQueue()
        _ = try AppDatabase(queue)
        let done = try queue.read { try AppDatabase.migrator.hasCompletedMigrations($0) }
        XCTAssertTrue(done)
    }

    // MARK: - Schema v2 (honest provenance + photo reorder)

    func testMigrationToV2AddsProvenanceColumns() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.read { db in
            XCTAssertTrue(try db.columns(in: "trip").map(\.name).contains("source"))
            XCTAssertTrue(try db.columns(in: "segment").map(\.name).contains("source"))
            XCTAssertTrue(try db.columns(in: "photo_ref").map(\.name).contains("order_idx"))
        }
    }

    /// The real old→new test: legacy rows written under v1 must survive v2 with
    /// the honest defaults — every existing trip stays `recorded`, and the
    /// nullable columns stay NULL.
    func testV2BackfillsLegacyRowsWithHonestDefaults() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v1")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO trip (id, title, started_at, status) VALUES ('t1', 'Legacy', 0, 'completed')")
            try db.execute(sql: "INSERT INTO segment (id, trip_id, mode, started_at) VALUES ('s1', 't1', 'drive', 0)")
            try db.execute(sql: "INSERT INTO photo_ref (id, trip_id, ph_asset_id) VALUES ('p1', 't1', 'asset1')")
        }

        try AppDatabase.migrator.migrate(queue)

        try queue.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT source FROM trip WHERE id = 't1'"), "recorded")
            // Nullable columns: fetchOne returns nil for a NULL value in an existing row.
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT source FROM segment WHERE id = 's1'"))
            XCTAssertNil(try Int.fetchOne(db, sql: "SELECT order_idx FROM photo_ref WHERE id = 'p1'"))
        }
    }

    func testProvenanceRecordsRoundTrip() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            try TripRecord(id: "t1", title: "Iceland", startedAt: 0, status: "completed",
                           source: TripSource.importedPhotos.rawValue).insert(db)
            try SegmentRecord(id: "s1", tripId: "t1", mode: "drive", startedAt: 0,
                              source: SegmentSource.exif.rawValue).insert(db)
            try PhotoRefRecord(id: "p1", tripId: "t1", stopId: nil, phAssetId: "asset1",
                               isHighlight: 1, orderIdx: 2).insert(db)
        }

        try database.writer.read { db in
            let trip = try XCTUnwrap(try TripRecord.fetchOne(db, key: "t1"))
            XCTAssertEqual(trip.tripSource, .importedPhotos)
            XCTAssertTrue(trip.tripSource.isReconstructed)

            let segment = try XCTUnwrap(try SegmentRecord.fetchOne(db, key: "s1"))
            XCTAssertEqual(segment.segmentSource, .exif)

            let photo = try XCTUnwrap(try PhotoRefRecord.fetchOne(db, key: "p1"))
            XCTAssertEqual(photo.orderIdx, 2)
        }
    }

    /// A recorded trip and a legacy trip both read as `.recorded` — the default
    /// must never accidentally mislabel a genuine recording as reconstructed.
    func testDefaultAndLegacyTripsReadAsRecorded() throws {
        XCTAssertEqual(TripSource(storage: nil), .recorded)
        XCTAssertEqual(TripSource(storage: "surprise_future_value"), .recorded)
        XCTAssertFalse(TripSource.recorded.isReconstructed)
        XCTAssertEqual(SegmentSource(storage: nil), .gpsHifi)
    }
}
