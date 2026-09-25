import Foundation
import GRDB

/// The person's film choices on photographs (ADR 2026-09-24), split out of
/// `TripRepository` for its size budget, like the other extension files.
extension TripRepository {
    /// Sets what the film does with one photograph (ADR 2026-09-24). The two
    /// columns are written together so a photograph is never both starred and
    /// excluded: leaving out a Photos favourite clears its star in Kamome only
    /// — the photo library is never written.
    public func setPhotoFilmChoice(photoId: String, choice: PhotoRefRecord.FilmChoice) throws {
        let (highlight, excluded) = switch choice {
        case .auto: (0, 0)
        case .starred: (1, 0)
        case .excluded: (0, 1)
        }
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE photo_ref SET is_highlight = ?, is_excluded = ? WHERE id = ?",
                arguments: [highlight, excluded, photoId]
            )
        }
    }

    // MARK: - Reading and replacing (moved from `TripRepository`, size budget)

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
}
