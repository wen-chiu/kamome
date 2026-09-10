import Foundation
import GRDB
import XCTest

@testable import KamomePersistence

/// Phase 4 closeout (Chiu 2026-09-05): a finished film is a thing that exists.
/// These prove the record layer — the DB half of the storage guarantee.
final class FilmPersistenceTests: XCTestCase {

    // MARK: - 1. Film record round-trip

    /// A film record survives a TripRepository round-trip: insert, read back,
    /// and every field is what was written.
    func testFilmRecordSurvivesRoundTrip() throws {
        let database = try AppDatabase.inMemory()
        let repository = TripRepository(database: database)
        let tripId = try repository.saveCompletedTrip(
            title: "Miyakojima",
            startedAt: 1_752_600_000,
            endedAt: 1_752_640_000,
            segments: [],
            stops: []
        )

        let film = FilmRecord(
            id: "film-1",
            tripId: tripId,
            relativePath: "Films/kamome-recap-1752640000.mp4",
            format: "mp4",
            createdAt: 1_752_640_100,
            durationS: 72.5,
            renderSeconds: 45.3,
            appearance: "dark",
            recapMode: "highlight",
            fileBytes: 56_000_000
        )
        try repository.saveFilm(film)

        let films = try repository.films(tripId: tripId)
        XCTAssertEqual(films.count, 1)
        let read = try XCTUnwrap(films.first)
        XCTAssertEqual(read.id, "film-1")
        XCTAssertEqual(read.tripId, tripId)
        XCTAssertEqual(read.relativePath, "Films/kamome-recap-1752640000.mp4")
        XCTAssertEqual(read.format, "mp4")
        XCTAssertEqual(read.createdAt, 1_752_640_100)
        XCTAssertEqual(read.durationS, 72.5)
        XCTAssertEqual(read.renderSeconds, 45.3)
        XCTAssertEqual(read.appearance, "dark")
        XCTAssertEqual(read.recapMode, "highlight")
        XCTAssertEqual(read.fileBytes, 56_000_000)
    }

    /// Multiple films for the same trip are returned newest first.
    func testMultipleFilmsForOneTripReturnNewestFirst() throws {
        let database = try AppDatabase.inMemory()
        let repository = TripRepository(database: database)
        let tripId = try repository.saveCompletedTrip(
            title: "Ishigaki", startedAt: 0, endedAt: 1_000, segments: [], stops: []
        )

        try repository.saveFilm(FilmRecord(
            id: "old", tripId: tripId, relativePath: "Films/old.mp4",
            format: "mp4", createdAt: 100, appearance: "light", recapMode: "highlight"
        ))
        try repository.saveFilm(FilmRecord(
            id: "new", tripId: tripId, relativePath: "Films/new.mp4",
            format: "mp4", createdAt: 200, appearance: "dark", recapMode: "full"
        ))

        let films = try repository.films(tripId: tripId)
        XCTAssertEqual(films.count, 2)
        XCTAssertEqual(films[0].id, "new", "newest first")
        XCTAssertEqual(films[1].id, "old")
    }

    // MARK: - 2. Relative path resolves correctly against a different root

    /// A stored relative path resolves correctly when rebuilt against a
    /// DIFFERENT container root — this is the app-update bug: the iOS app
    /// container path changes across updates and restores, so a stored
    /// absolute URL silently stops resolving.
    func testRelativePathResolvesAgainstDifferentContainerRoot() throws {
        let relativePath = "Films/kamome-recap-1752640000.mp4"

        // Simulate two different container UUIDs — same relative path, different
        // absolute roots. Both must resolve to a URL ending in the relative path.
        let root1 = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/AAA-BBB/Library/Application Support")
        let root2 = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/CCC-DDD/Library/Application Support")

        let url1 = root1.appendingPathComponent(relativePath)
        let url2 = root2.appendingPathComponent(relativePath)

        XCTAssertNotEqual(url1, url2, "different roots must produce different absolute URLs")
        XCTAssertTrue(url1.path.hasSuffix(relativePath))
        XCTAssertTrue(url2.path.hasSuffix(relativePath))
        XCTAssertTrue(url1.path.contains("AAA-BBB"))
        XCTAssertTrue(url2.path.contains("CCC-DDD"))
    }

    // MARK: - 3. Deleting a trip removes its film rows and its files

    /// Deleting a trip removes its film rows. The caller is responsible for
    /// removing the files — `deleteTrip` returns the deleted film records so
    /// the file cleanup can happen outside the database transaction.
    func testDeleteTripRemovesFilmRows() throws {
        let database = try AppDatabase.inMemory()
        let repository = TripRepository(database: database)
        let tripId = try repository.saveCompletedTrip(
            title: "Perth", startedAt: 0, endedAt: 10_000,
            segments: [
                TripRepository.NewSegment(mode: "drive", startedAt: 0, endedAt: 1_000, points: [
                    TripRepository.NewTrackpoint(ts: 0, lat: -31.95, lon: 115.86)
                ])
            ],
            stops: [
                TripRepository.NewStop(lat: -32.0, lon: 115.87, arrivedAt: 1_000, departedAt: 2_000)
            ]
        )

        // Two films for this trip.
        try repository.saveFilm(FilmRecord(
            id: "f1", tripId: tripId, relativePath: "Films/f1.mp4",
            format: "mp4", createdAt: 100, appearance: "light", recapMode: "highlight"
        ))
        try repository.saveFilm(FilmRecord(
            id: "f2", tripId: tripId, relativePath: "Films/f2.gif",
            format: "gif", createdAt: 200, appearance: "dark", recapMode: "full"
        ))

        // A second trip that must NOT be affected.
        let otherTripId = try repository.saveCompletedTrip(
            title: "Unrelated", startedAt: 20_000, endedAt: 30_000,
            segments: [], stops: []
        )
        try repository.saveFilm(FilmRecord(
            id: "f3", tripId: otherTripId, relativePath: "Films/f3.mp4",
            format: "mp4", createdAt: 300, appearance: "light", recapMode: "highlight"
        ))

        let deleted = try repository.deleteTrip(tripId: tripId)

        // The deleted trip's film records are returned for file cleanup.
        XCTAssertEqual(Set(deleted.map(\.id)), ["f1", "f2"])
        XCTAssertEqual(Set(deleted.map(\.relativePath)), ["Films/f1.mp4", "Films/f2.gif"])

        // The trip and everything it owns is gone.
        XCTAssertNil(try repository.detail(tripId: tripId))
        XCTAssertEqual(try repository.films(tripId: tripId).count, 0)

        // The other trip is untouched.
        XCTAssertNotNil(try repository.detail(tripId: otherTripId))
        XCTAssertEqual(try repository.films(tripId: otherTripId).count, 1)
    }

    /// Deleting a trip cascades to all related rows: trackpoints, segments,
    /// photos, stops, and films.
    func testDeleteTripCascadesToAllRelatedRows() throws {
        let database = try AppDatabase.inMemory()
        let repository = TripRepository(database: database)
        let tripId = try repository.saveCompletedTrip(
            title: "Cascade", startedAt: 0, endedAt: 10_000,
            segments: [
                TripRepository.NewSegment(mode: "drive", startedAt: 0, endedAt: 5_000, points: [
                    TripRepository.NewTrackpoint(ts: 0, lat: -31.95, lon: 115.86),
                    TripRepository.NewTrackpoint(ts: 1_000, lat: -32.00, lon: 115.87)
                ])
            ],
            stops: [
                TripRepository.NewStop(lat: -32.0, lon: 115.87, arrivedAt: 1_000, departedAt: 2_000)
            ]
        )
        try repository.replacePhotoRefs(tripId: tripId, with: [
            PhotoRefRecord(id: "ph1", tripId: tripId, stopId: nil, phAssetId: "asset-1")
        ])
        try repository.saveFilm(FilmRecord(
            id: "f1", tripId: tripId, relativePath: "Films/f1.mp4",
            format: "mp4", createdAt: 100, appearance: "light", recapMode: "highlight"
        ))

        _ = try repository.deleteTrip(tripId: tripId)

        XCTAssertEqual(try repository.allTrips().count, 0)
        XCTAssertEqual(try repository.stopCount(tripId: tripId), 0)
        XCTAssertEqual(try repository.segmentCount(tripId: tripId), 0)
        XCTAssertEqual(try repository.trackpointCount(tripId: tripId), 0)
        XCTAssertEqual(try repository.films(tripId: tripId).count, 0)
        XCTAssertEqual(try repository.photoRefs(tripId: tripId).count, 0)
    }

    /// Deleting a single film removes only its row.
    func testDeleteFilmRemovesOnlyItsRow() throws {
        let database = try AppDatabase.inMemory()
        let repository = TripRepository(database: database)
        let tripId = try repository.saveCompletedTrip(
            title: "Single", startedAt: 0, endedAt: 1_000, segments: [], stops: []
        )
        try repository.saveFilm(FilmRecord(
            id: "keep", tripId: tripId, relativePath: "Films/keep.mp4",
            format: "mp4", createdAt: 100, appearance: "light", recapMode: "highlight"
        ))
        try repository.saveFilm(FilmRecord(
            id: "delete-me", tripId: tripId, relativePath: "Films/delete.mp4",
            format: "mp4", createdAt: 200, appearance: "dark", recapMode: "full"
        ))

        let deleted = try repository.deleteFilm(filmId: "delete-me")
        XCTAssertEqual(deleted?.id, "delete-me")

        let remaining = try repository.films(tripId: tripId)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].id, "keep")
    }

    // MARK: - Schema v5

    func testMigrationToV5CreatesFilmTableAndIndex() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.read { db in
            let tables = try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            XCTAssertTrue(tables.contains("film"), "film table missing after migration v5")

            let indexes = try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index'")
            XCTAssertTrue(indexes.contains("idx_film_trip"), "idx_film_trip index missing")
        }
    }

    func testV5LeavesExistingDataIntact() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v4")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO trip (id, title, started_at, status, source)
                VALUES ('t1', 'Pre-v5', 0, 'completed', 'recorded')
                """)
        }
        try AppDatabase.migrator.migrate(queue)

        try queue.read { db in
            XCTAssertEqual(try String.fetchOne(db, sql: "SELECT title FROM trip WHERE id = 't1'"), "Pre-v5")
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM film"), 0)
        }
    }
}
