import Foundation
import GRDB

/// Trip merge (ADR 2026-09-24): several trips become one, so a journey that
/// was recorded day by day, or partly recorded and partly rebuilt from
/// photographs, can be one film.
///
/// The repository only *applies* a merge. Deciding what goes between two trips
/// (an overnight stop, or a gap leg) is `TripMerger`'s job in the app, because
/// it needs geometry this module does not have.
extension TripRepository {
    public struct TripMerge {
        /// The trip that survives, keeping its id, title, vehicle and place
        /// name. The caller chooses the earliest.
        public let keptId: String
        /// Trips folded into `keptId`, then deleted.
        public let absorbedIds: [String]
        public let startedAt: Double
        public let endedAt: Double
        /// `TripSource` raw value of the whole. Reconstructed if any part is.
        public let source: String
        /// nil clears the stats. A trip containing reconstructed days has no
        /// measured total to show.
        public let statsJson: String?
        /// Kept when the survivor has none of its own, so Discovery still
        /// recognises one of the journeys the parts came from.
        public let discoveryKey: String?
        /// Gap legs between parts that ended and began far apart.
        public let gapSegments: [NewSegment]
        /// Overnight stops between parts that ended and began in one place.
        public let junctionStops: [NewStop]
        /// A part's last stop stretched to cover the night, instead of a new one.
        public let stopDepartures: [(stopId: String, departedAt: Double)]

        public init(
            keptId: String,
            absorbedIds: [String],
            startedAt: Double,
            endedAt: Double,
            source: String,
            statsJson: String?,
            discoveryKey: String?,
            gapSegments: [NewSegment],
            junctionStops: [NewStop],
            stopDepartures: [(stopId: String, departedAt: Double)]
        ) {
            self.keptId = keptId
            self.absorbedIds = absorbedIds
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.source = source
            self.statsJson = statsJson
            self.discoveryKey = discoveryKey
            self.gapSegments = gapSegments
            self.junctionStops = junctionStops
            self.stopDepartures = stopDepartures
        }
    }

    /// Applies a merge in one transaction. Either every row moves or none does.
    ///
    /// Segments keep their ids, geometry, `source` and routing verdicts, so a
    /// road already matched is not asked again and a reconstructed leg stays
    /// marked as reconstructed. Photos keep their stop links and highlights.
    /// **Films move too** (Chiu 2026-09-24): a film of one day stays listed on
    /// the merged trip rather than being deleted.
    public func applyMerge(_ merge: TripMerge) throws {
        try database.writer.write { db in
            guard try TripRecord.fetchOne(db, key: merge.keptId) != nil else {
                throw MergeError.missingTrip
            }
            for absorbed in merge.absorbedIds {
                guard try TripRecord.fetchOne(db, key: absorbed) != nil else { throw MergeError.missingTrip }
                for table in ["segment", "stop", "photo_ref", "film"] {
                    try db.execute(
                        sql: "UPDATE \(table) SET trip_id = ? WHERE trip_id = ?",
                        arguments: [merge.keptId, absorbed]
                    )
                }
                try db.execute(sql: "DELETE FROM trip WHERE id = ?", arguments: [absorbed])
            }
            for segment in merge.gapSegments {
                try insertSegment(segment, tripId: merge.keptId, into: db)
            }
            for stop in merge.junctionStops {
                try StopRecord(
                    id: UUID().uuidString, tripId: merge.keptId,
                    lat: stop.lat, lon: stop.lon,
                    arrivedAt: stop.arrivedAt, departedAt: stop.departedAt,
                    kind: stop.kind
                ).insert(db)
            }
            for update in merge.stopDepartures {
                try db.execute(
                    sql: "UPDATE stop SET departed_at = ? WHERE id = ? AND trip_id = ?",
                    arguments: [update.departedAt, update.stopId, merge.keptId]
                )
            }
            try db.execute(
                sql: """
                    UPDATE trip SET started_at = ?, ended_at = ?, source = ?, stats_json = ?,
                    discovery_key = COALESCE(discovery_key, ?) WHERE id = ?
                    """,
                arguments: [
                    merge.startedAt, merge.endedAt, merge.source, merge.statsJson,
                    merge.discoveryKey, merge.keptId
                ]
            )
        }
    }

    public enum MergeError: Error, Equatable {
        case missingTrip
    }
}
