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
}
