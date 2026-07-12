import Foundation
import GRDB

/// Repositories are the only layer that touches GRDB (spec §8).
/// TripRepository persists a completed recording session and lists trips
/// for S1. Input types are plain values so the repository does not depend
/// on the tracking engine module.
public struct TripRepository {
    public struct NewSegment {
        public let mode: String
        public let startedAt: Double
        public let endedAt: Double?
        public let points: [NewTrackpoint]

        public init(mode: String, startedAt: Double, endedAt: Double?, points: [NewTrackpoint]) {
            self.mode = mode
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.points = points
        }
    }

    public struct NewTrackpoint {
        public let ts: Double
        public let lat: Double
        public let lon: Double
        public let hAcc: Double?
        public let speed: Double?
        public let course: Double?
        public let altitude: Double?

        public init(
            ts: Double,
            lat: Double,
            lon: Double,
            hAcc: Double? = nil,
            speed: Double? = nil,
            course: Double? = nil,
            altitude: Double? = nil
        ) {
            self.ts = ts
            self.lat = lat
            self.lon = lon
            self.hAcc = hAcc
            self.speed = speed
            self.course = course
            self.altitude = altitude
        }
    }

    public struct NewStop {
        public let lat: Double
        public let lon: Double
        public let arrivedAt: Double
        public let departedAt: Double?

        public init(lat: Double, lon: Double, arrivedAt: Double, departedAt: Double?) {
            self.lat = lat
            self.lon = lon
            self.arrivedAt = arrivedAt
            self.departedAt = departedAt
        }
    }

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Persists one completed recording atomically. Returns the trip id.
    @discardableResult
    public func saveCompletedTrip(
        title: String,
        startedAt: Double,
        endedAt: Double,
        segments: [NewSegment],
        stops: [NewStop]
    ) throws -> String {
        let tripId = UUID().uuidString
        try database.writer.write { db in
            try TripRecord(
                id: tripId,
                title: title,
                startedAt: startedAt,
                endedAt: endedAt,
                status: "completed"
            ).insert(db)

            for segment in segments {
                let segmentId = UUID().uuidString
                try SegmentRecord(
                    id: segmentId,
                    tripId: tripId,
                    mode: segment.mode,
                    startedAt: segment.startedAt,
                    endedAt: segment.endedAt
                ).insert(db)
                let points = segment.points.map { point in
                    TrackpointRecord(
                        segmentId: segmentId,
                        ts: point.ts,
                        lat: point.lat,
                        lon: point.lon,
                        hAcc: point.hAcc,
                        speed: point.speed,
                        course: point.course,
                        altitude: point.altitude
                    )
                }
                try TrackpointRecord.bulkInsert(points, into: db)
            }

            for stop in stops {
                try StopRecord(
                    id: UUID().uuidString,
                    tripId: tripId,
                    lat: stop.lat,
                    lon: stop.lon,
                    arrivedAt: stop.arrivedAt,
                    departedAt: stop.departedAt,
                    kind: "auto"
                ).insert(db)
            }
        }
        return tripId
    }

    /// Trips for the S1 list, newest first.
    public func allTrips() throws -> [TripRecord] {
        try database.writer.read { db in
            try TripRecord.order(sql: "started_at DESC").fetchAll(db)
        }
    }

    public func stopCount(tripId: String) throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM stop WHERE trip_id = ?", arguments: [tripId]) ?? 0
        }
    }

    public func segmentCount(tripId: String) throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM segment WHERE trip_id = ?", arguments: [tripId]) ?? 0
        }
    }

    public func trackpointCount(tripId: String) throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM trackpoint
                    WHERE segment_id IN (SELECT id FROM segment WHERE trip_id = ?)
                    """,
                arguments: [tripId]
            ) ?? 0
        }
    }
}
