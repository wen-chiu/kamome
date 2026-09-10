import Foundation
import GRDB

/// Film persistence (schema v5, Phase 4 closeout), split out of
/// `TripRepository` for the same reason every other extension file was: the
/// type has a size budget, and films belong to a different question than
/// recording a trip does.
extension TripRepository {
    /// Persists a finished film's record.
    public func saveFilm(_ film: FilmRecord) throws {
        try database.writer.write { db in
            try film.insert(db)
        }
    }

    /// All films for a trip, newest first.
    public func films(tripId: String) throws -> [FilmRecord] {
        try database.writer.read { db in
            try FilmRecord
                .filter(sql: "trip_id = ?", arguments: [tripId])
                .order(sql: "created_at DESC")
                .fetchAll(db)
        }
    }

    /// Deletes one film row and returns the deleted record so the caller can
    /// clean up the file on disk. Returns nil when the id does not exist.
    @discardableResult
    public func deleteFilm(filmId: String) throws -> FilmRecord? {
        try database.writer.write { db in
            guard let film = try FilmRecord.fetchOne(db, key: filmId) else { return nil }
            try film.delete(db)
            return film
        }
    }

    /// Deletes a trip and everything it owns: films, photos, stops, segments,
    /// and trackpoints. Returns the deleted film records so the caller can
    /// remove their files — an orphaned 56 MB file is the failure mode this
    /// cascade prevents.
    ///
    /// The ordering matters: trackpoints reference segments, photos reference
    /// stops and the trip, and everything else references the trip. Delete
    /// leaves before the trunk.
    @discardableResult
    public func deleteTrip(tripId: String) throws -> [FilmRecord] {
        try database.writer.write { db in
            let films = try FilmRecord
                .filter(sql: "trip_id = ?", arguments: [tripId])
                .fetchAll(db)
            // Trackpoints → segments (leaves first)
            try db.execute(sql: """
                DELETE FROM trackpoint
                WHERE segment_id IN (SELECT id FROM segment WHERE trip_id = ?)
                """, arguments: [tripId])
            try db.execute(sql: "DELETE FROM segment WHERE trip_id = ?", arguments: [tripId])
            try db.execute(sql: "DELETE FROM photo_ref WHERE trip_id = ?", arguments: [tripId])
            try db.execute(sql: "DELETE FROM stop WHERE trip_id = ?", arguments: [tripId])
            try db.execute(sql: "DELETE FROM film WHERE trip_id = ?", arguments: [tripId])
            try db.execute(sql: "DELETE FROM trip WHERE id = ?", arguments: [tripId])
            return films
        }
    }
}
