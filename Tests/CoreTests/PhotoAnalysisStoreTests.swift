import GRDB
import XCTest

@testable import KamomePersistence

/// Schema v11 — what Vision found, per asset (ADR 2026-09-25 (c)).
final class PhotoAnalysisStoreTests: XCTestCase {
    /// One trip, one stop, three photographs at it and one on the route.
    private func seeded() throws -> (TripRepository, AppDatabase) {
        let database = try AppDatabase.inMemory()
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO trip (id, title, started_at, status) VALUES ('t1', 'Trip', 0, 'completed');
                INSERT INTO stop (id, trip_id, lat, lon, arrived_at) VALUES ('s1', 't1', 0, 0, 0);
                INSERT INTO photo_ref (id, trip_id, stop_id, ph_asset_id, taken_at) VALUES
                  ('p1', 't1', 's1', 'a1', 1), ('p2', 't1', 's1', 'a2', 2), ('p3', 't1', 's1', 'a3', 3),
                  ('p4', 't1', NULL, 'route', 4);
                """)
        }
        return (TripRepository(database: database), database)
    }

    private func row(_ asset: String, version: Int = 1, outcome: PhotoAnalysisRecord.Outcome = .analyzed)
        -> PhotoAnalysisRecord {
        PhotoAnalysisRecord(
            phAssetId: asset, version: version, outcome: outcome, isUtility: 0, quality: 0.25,
            featurePrint: PhotoAnalysisRecord.encode(featurePrint: [1.5, -2, 0]), analyzedAt: 10
        )
    }

    func testMigrationToV11CreatesTheAnalysisTable() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.read { db in
            let columns = try db.columns(in: "photo_analysis").map(\.name)
            XCTAssertEqual(
                Set(columns),
                ["ph_asset_id", "version", "outcome", "is_utility", "quality", "feature_print", "analyzed_at"]
            )
        }
    }

    func testARowRoundTripsWithItsFeaturePrint() throws {
        let (repository, _) = try seeded()
        try repository.savePhotoAnalysis(row("a1"))
        let read = try XCTUnwrap(try repository.photoAnalyses(tripId: "t1")["a1"])
        XCTAssertEqual(read, row("a1"))
        XCTAssertEqual(read.featurePrintFloats, [1.5, -2, 0])
        XCTAssertEqual(try repository.detail(tripId: "t1")?.analyses.keys.sorted(), ["a1"])
    }

    /// A run resumes where it stopped, re-asks the ones that had no pixels, and
    /// redoes rows from an older analyser. Route photographs are never asked.
    func testOnlyStopPhotographsStillWaitingAreAnalysed() throws {
        let (repository, _) = try seeded()
        XCTAssertEqual(try repository.assetsNeedingAnalysis(tripId: "t1", version: 1), ["a1", "a2", "a3"])
        try repository.savePhotoAnalysis(row("a1"))
        try repository.savePhotoAnalysis(row("a2", outcome: .unavailable))
        XCTAssertEqual(try repository.assetsNeedingAnalysis(tripId: "t1", version: 1), ["a2", "a3"])
        try repository.savePhotoAnalysis(row("a3"))
        XCTAssertEqual(try repository.assetsNeedingAnalysis(tripId: "t1", version: 2), ["a1", "a2", "a3"])
    }

    /// Deleting the last trip holding a photograph deletes what Vision found in it.
    func testDeletingATripSweepsItsAnalysis() throws {
        let (repository, database) = try seeded()
        try repository.savePhotoAnalysis(row("a1"))
        try repository.savePhotoAnalysis(row("elsewhere"))
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO trip (id, title, started_at, status) VALUES ('t2', 'Other', 0, 'completed');
                INSERT INTO photo_ref (id, trip_id, ph_asset_id) VALUES ('q1', 't2', 'elsewhere');
                """)
        }
        _ = try repository.deleteTrip(tripId: "t1")
        let left = try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT ph_asset_id FROM photo_analysis")
        }
        XCTAssertEqual(left, ["elsewhere"], "another trip's photograph keeps its row")
    }
}
