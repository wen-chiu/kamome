import Foundation
import GRDB

/// Reads the Journey Discovery home needs (2026-09-17), split out for the same
/// reason every other extension file was: the type has a size budget.
extension TripRepository {
    /// The trip made from a discovered journey, if one exists. This is what
    /// keeps a rescan from importing the same journey twice.
    public func trip(discoveryKey: String) throws -> TripRecord? {
        try database.writer.read { db in
            try TripRecord
                .filter(sql: "discovery_key = ?", arguments: [discoveryKey])
                .fetchOne(db)
        }
    }

    /// Everything a journey card shows about a stored trip, in one read.
    public struct JourneyCardFacts: Equatable {
        /// Every photograph, in the order it was taken.
        public let photos: [PhotoRefRecord]
        public let stopCount: Int
        public let filmCount: Int
        /// Leg transport modes, in trip order (`TransportMode` raw values).
        public let legModes: [String]
        /// The named stops, in trip order — the journey's milestones. Unnamed
        /// stops are left out rather than filled with a placeholder: the
        /// timeline says "3 places" when it does not know them yet, which is
        /// true, where "Unnamed stop › Unnamed stop" is noise.
        public let stopNames: [String]
        /// The busiest stop's position — where the journey's name is looked up.
        public let nameLookupLat: Double?
        public let nameLookupLon: Double?
        /// The stops' bounding box; the caller turns it into metres. nil with no stops.
        public let stopSpan: StopSpan?
    }

    /// A bounding box in degrees — the persistence layer does no geodesy.
    public struct StopSpan: Equatable {
        public let minLat: Double
        public let maxLat: Double
        public let minLon: Double
        public let maxLon: Double

        public var latDeg: Double { maxLat - minLat }
        public var lonDeg: Double { maxLon - minLon }
    }

    public func journeyCardFacts(tripId: String) throws -> JourneyCardFacts {
        try database.writer.read { db in
            let photos = try PhotoRefRecord
                .filter(sql: "trip_id = ?", arguments: [tripId])
                .order(sql: "taken_at")
                .fetchAll(db)
            let stops = try StopRecord
                .filter(sql: "trip_id = ?", arguments: [tripId])
                .order(sql: "arrived_at")
                .fetchAll(db)
            let filmCount = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM film WHERE trip_id = ?", arguments: [tripId]
            ) ?? 0
            let modes = try String.fetchAll(
                db, sql: "SELECT mode FROM segment WHERE trip_id = ? ORDER BY started_at", arguments: [tripId]
            )
            // The stop with the most photographs is the place the journey was
            // about; ties go to the earliest.
            let busiest = try Row.fetchOne(db, sql: """
                SELECT s.lat AS lat, s.lon AS lon FROM stop s
                LEFT JOIN photo_ref p ON p.stop_id = s.id
                WHERE s.trip_id = ?
                GROUP BY s.id ORDER BY COUNT(p.id) DESC, s.arrived_at ASC LIMIT 1
                """, arguments: [tripId])
            let span = try Row.fetchOne(db, sql: """
                SELECT MIN(lat) AS minLat, MAX(lat) AS maxLat, MIN(lon) AS minLon, MAX(lon) AS maxLon
                FROM stop WHERE trip_id = ?
                """, arguments: [tripId])
            var stopSpan: StopSpan?
            if let span, let minLat: Double = span["minLat"], let maxLat: Double = span["maxLat"],
               let minLon: Double = span["minLon"], let maxLon: Double = span["maxLon"] {
                stopSpan = StopSpan(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
            }
            return JourneyCardFacts(
                photos: photos,
                stopCount: stops.count,
                filmCount: filmCount,
                legModes: modes,
                stopNames: stops.compactMap(\.name),
                nameLookupLat: busiest?["lat"],
                nameLookupLon: busiest?["lon"],
                stopSpan: stopSpan
            )
        }
    }
}
