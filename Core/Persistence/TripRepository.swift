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

    /// Everything S3 needs for one trip.
    public struct TripDetail {
        public let trip: TripRecord
        public let segments: [(segment: SegmentRecord, points: [TrackpointRecord])]
        public let stops: [StopRecord]
        public let photos: [PhotoRefRecord]
    }

    public func detail(tripId: String) throws -> TripDetail? {
        try database.writer.read { db in
            guard let trip = try TripRecord.fetchOne(db, key: tripId) else { return nil }
            let segments = try SegmentRecord
                .filter(sql: "trip_id = ?", arguments: [tripId])
                .order(sql: "started_at")
                .fetchAll(db)
            let withPoints = try segments.map { segment in
                (segment: segment, points: try TrackpointRecord
                    .filter(sql: "segment_id = ?", arguments: [segment.id])
                    .order(sql: "ts")
                    .fetchAll(db))
            }
            let stops = try StopRecord
                .filter(sql: "trip_id = ?", arguments: [tripId])
                .order(sql: "arrived_at")
                .fetchAll(db)
            let photos = try PhotoRefRecord
                .filter(sql: "trip_id = ?", arguments: [tripId])
                .fetchAll(db)
            return TripDetail(trip: trip, segments: withPoints, stops: stops, photos: photos)
        }
    }

    public func updateTripStats(tripId: String, statsJson: String) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "UPDATE trip SET stats_json = ? WHERE id = ?",
                arguments: [statsJson, tripId]
            )
        }
    }

    // MARK: - Stops (S4 Stop Editor)

    public func setStopName(stopId: String, name: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE stop SET name = ? WHERE id = ?", arguments: [name, stopId])
        }
    }

    public func setStopNote(stopId: String, note: String?) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE stop SET note = ? WHERE id = ?", arguments: [note, stopId])
        }
    }

    /// Deletes a false-positive stop; its photos become route-attached.
    public func deleteStop(stopId: String) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE photo_ref SET stop_id = NULL WHERE stop_id = ?", arguments: [stopId])
            try db.execute(sql: "DELETE FROM stop WHERE id = ?", arguments: [stopId])
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
        }
    }

    // MARK: - Photos

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

    /// Self-contained database copy for the debug export path
    /// (Docs/device-test-P1.md post-drive verification).
    public func snapshotDatabase(to path: String) throws {
        try database.snapshot(to: path)
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
