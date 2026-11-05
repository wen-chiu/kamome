import Foundation
import GRDB
import XCTest

@testable import KamomePersistence

/// **Schema v17 — the film's music** (`Docs/handoff-music-in-the-film.md` §4.3,
/// §2.4): one bump for the film's track and basis and the analyser's mood.
/// Rows from before read as silent films and as photographs with no mood.
final class SoundtrackSchemaTests: XCTestCase {
    func testV17KeepsEveryOlderRowAndReadsItAsSilentWithNoMood() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue, upTo: "v16")
        try queue.write { db in
            try db.execute(sql: "INSERT INTO trip (id, title, started_at, status) VALUES ('t1', 'Trip', 0, 'done')")
            try db.execute(sql: """
                INSERT INTO film (id, trip_id, relative_path, format, created_at, appearance, recap_mode, file_bytes)
                VALUES ('f1', 't1', 'Films/old.mp4', 'mp4', 1, 'dark', 'highlight', 42)
                """)
            try db.execute(sql: """
                INSERT INTO photo_analysis (ph_asset_id, version, outcome, quality, analyzed_at)
                VALUES ('a1', 1, 'analyzed', 0.5, 1)
                """)
        }
        try AppDatabase.migrator.migrate(queue)

        try queue.read { db in
            let film = try XCTUnwrap(FilmRecord.fetchOne(db, key: "f1"))
            XCTAssertEqual(film.relativePath, "Films/old.mp4")
            XCTAssertEqual(film.fileBytes, 42)
            XCTAssertNil(film.soundtrackId, "a film made before music is silent")
            XCTAssertNil(film.soundtrackPlanVersion)
            XCTAssertNil(film.soundtrackBasis, "and has no basis, so 「換音樂」 is not offered for it")
            let row = try XCTUnwrap(PhotoAnalysisRecord.fetchOne(db, key: "a1"))
            XCTAssertEqual(row.version, 1)
            XCTAssertEqual(row.quality, 0.5, "the pick signals survive")
            XCTAssertNil(row.sceneLabels)
            XCTAssertNil(row.luminance)
            XCTAssertNil(row.saturation)
            XCTAssertNil(row.warmth)
        }
    }

    func testV17AddsTheMusicColumns() throws {
        let database = try AppDatabase.inMemory()
        try database.writer.read { db in
            let film = Set(try db.columns(in: "film").map(\.name))
            XCTAssertTrue(Set(["soundtrack_id", "soundtrack_plan_version", "soundtrack_basis"]).isSubset(of: film))
            let analysis = Set(try db.columns(in: "photo_analysis").map(\.name))
            XCTAssertTrue(Set(["scene_labels", "luminance", "saturation", "warmth"]).isSubset(of: analysis))
        }
    }

    func testTheMusicColumnsRoundTripAndAChangeIsRecorded() throws {
        let database = try AppDatabase.inMemory()
        let repository = TripRepository(database: database)
        let tripId = try repository.saveCompletedTrip(title: "Trip", startedAt: 0, endedAt: 1, segments: [], stops: [])
        let film = FilmRecord(
            id: "f1", tripId: tripId, relativePath: "Films/a.mp4", format: "mp4", createdAt: 1, appearance: "light",
            recapMode: "highlight", fileBytes: 10, soundtrackId: "track-a", soundtrackPlanVersion: 1,
            soundtrackBasis: #"{"cues":[],"ranking":["track-a","track-b"]}"#
        )
        try repository.saveFilm(film)
        XCTAssertEqual(try repository.films(tripId: tripId), [film])

        let changed = try repository.setFilmSoundtrack(filmId: "f1", soundtrackId: nil, fileBytes: 9)
        XCTAssertNil(changed?.soundtrackId, "無音樂 is a silent film")
        XCTAssertEqual(changed?.fileBytes, 9)
        XCTAssertEqual(changed?.soundtrackBasis, film.soundtrackBasis, "the basis outlives a change")
        XCTAssertEqual(try repository.films(tripId: tripId), changed.map { [$0] })
        XCTAssertNil(try repository.setFilmSoundtrack(filmId: "gone", soundtrackId: "x", fileBytes: 1))
    }

    func testAnAnalysisRowKeepsItsMood() throws {
        let database = try AppDatabase.inMemory()
        let repository = TripRepository(database: database)
        let row = PhotoAnalysisRecord(
            phAssetId: "a1", version: 2, outcome: .analyzed, sceneLabels: 0b1000_0000_0000_0001,
            luminance: 0.4, saturation: 0.3, warmth: -0.1, analyzedAt: 1
        )
        try repository.savePhotoAnalysis(row)
        let read = try database.writer.read { try PhotoAnalysisRecord.fetchOne($0, key: "a1") }
        XCTAssertEqual(read, row)
    }
}
