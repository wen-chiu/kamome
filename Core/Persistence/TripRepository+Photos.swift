import Foundation
import GRDB

/// The person's film choices on photographs and stops (ADR 2026-09-24, Chiu
/// 2026-09-25), split out of `TripRepository` for its size budget, like the
/// other extension files.
extension TripRepository {
    // MARK: - Photo rows (moved from `TripRepository` for its length budget)

    public func photoRefs(tripId: String) throws -> [PhotoRefRecord] {
        try database.writer.read { db in
            try PhotoRefRecord
                .filter(sql: "trip_id = ?", arguments: [tripId])
                .fetchAll(db)
        }
    }

    public func replacePhotoRefs(tripId: String, with photos: [PhotoRefRecord]) throws {
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM photo_ref WHERE trip_id = ?", arguments: [tripId])
            for photo in photos {
                try photo.insert(db)
            }
        }
    }

    public func setPhotoHighlight(photoId: String, isHighlight: Bool) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE photo_ref SET is_highlight = ? WHERE id = ?",
                arguments: [isHighlight ? 1 : 0, photoId]
            )
        }
    }

    // MARK: - Film choices

    /// Sets what the film does with one photograph (ADR 2026-09-24). The two
    /// columns are written together so a photograph is never both starred and
    /// excluded: leaving out a Photos favourite clears its star in Kamome only
    /// — the photo library is never written. A photograph left out is no
    /// longer one of its stop's picks either.
    public func setPhotoFilmChoice(photoId: String, choice: PhotoRefRecord.FilmChoice) throws {
        let (highlight, excluded) = switch choice {
        case .auto: (0, 0)
        case .starred: (1, 0)
        case .excluded: (0, 1)
        }
        try database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE photo_ref SET is_highlight = ?, is_excluded = ?,
                    film_pick = CASE WHEN ? = 1 THEN 0 ELSE film_pick END WHERE id = ?
                    """,
                arguments: [highlight, excluded, excluded, photoId]
            )
        }
    }

    /// Replaces one stop's picks (Chiu 2026-09-25): exactly `photoIds` are
    /// picked, every other photograph at the stop is not. An empty list hands
    /// the deck back to the app. A picked photograph is never left out.
    public func setStopPicks(stopId: String, photoIds: [String]) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE photo_ref SET film_pick = 0 WHERE stop_id = ?", arguments: [stopId])
            for photoId in photoIds {
                try db.execute(
                    sql: "UPDATE photo_ref SET film_pick = 1, is_excluded = 0 WHERE id = ? AND stop_id = ?",
                    arguments: [photoId, stopId]
                )
            }
        }
    }

    /// Whether the film presents one stop (Chiu 2026-09-25); `nil` hands it
    /// back to the app's ranking. The stop's picks are kept either way, so a
    /// stop taken out and put back shows what it showed before.
    public func setStopFilmChoice(stopId: String, choice: StopRecord.StopFilmChoice?) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE stop SET film_choice = ? WHERE id = ?",
                arguments: [choice?.rawValue, stopId]
            )
        }
    }
}
