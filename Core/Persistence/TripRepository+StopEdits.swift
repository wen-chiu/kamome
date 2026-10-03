import Foundation
import GRDB

/// The Stop Editor's two destructive edits (S4). They live apart from
/// `TripRepository` so the struct stays inside its lint length, and so the one
/// rule they share, that the stored stop count follows the stops, sits beside them.
extension TripRepository {
    /// The stored `stop_count` follows the stops. `stats_json` is written once at
    /// completion, and Home's row and Trip Detail's strip read the count from it,
    /// so an edit that changes the number of stops must change it too (#211).
    /// Distance and times stay as recorded. A trip with no stats (an import) or
    /// stats that are not JSON is left alone, and never fails the edit.
    static func refreshStoredStopCount(_ db: Database, tripId: String) throws {
        try db.execute(
            sql: """
                UPDATE trip
                SET stats_json = json_set(stats_json, '$.stop_count',
                                          (SELECT COUNT(*) FROM stop WHERE trip_id = ?1))
                WHERE id = ?1 AND stats_json IS NOT NULL AND json_valid(stats_json)
                """,
            arguments: [tripId]
        )
    }

    /// Deletes a false-positive stop; its photos become route-attached.
    public func deleteStop(stopId: String) throws {
        try database.writer.write { db in
            let tripId = try String.fetchOne(db, sql: "SELECT trip_id FROM stop WHERE id = ?", arguments: [stopId])
            try db.execute(sql: "UPDATE photo_ref SET stop_id = NULL WHERE stop_id = ?", arguments: [stopId])
            try db.execute(sql: "DELETE FROM stop WHERE id = ?", arguments: [stopId])
            if let tripId { try Self.refreshStoredStopCount(db, tripId: tripId) }
        }
    }

    /// Merges `absorbedId` into `keptId`: earliest arrival, latest departure,
    /// photos reassigned.
    public func mergeStops(keptId: String, absorbedId: String) throws {
        try database.writer.write { db in
            guard
                let kept = try StopRecord.fetchOne(db, key: keptId),
                let absorbed = try StopRecord.fetchOne(db, key: absorbedId)
            else { return }
            let arrived = min(kept.arrivedAt, absorbed.arrivedAt)
            let departed: Double?
            switch (kept.departedAt, absorbed.departedAt) {
            case let (keptEnd?, absorbedEnd?): departed = max(keptEnd, absorbedEnd)
            default: departed = nil // one is still open-ended
            }
            try db.execute(
                sql: "UPDATE stop SET arrived_at = ?, departed_at = ? WHERE id = ?",
                arguments: [arrived, departed, keptId]
            )
            try db.execute(
                sql: "UPDATE photo_ref SET stop_id = ? WHERE stop_id = ?",
                arguments: [keptId, absorbedId]
            )
            try db.execute(sql: "DELETE FROM stop WHERE id = ?", arguments: [absorbedId])
            try Self.refreshStoredStopCount(db, tripId: absorbed.tripId)
        }
    }
}
