import Foundation
import GRDB

/// Row types mirroring schema v1 (spec §3). Phase 0 defines only what the
/// round-trip test needs; further records arrive with the phases that use them.
public struct TripRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "trip"

    public var id: String
    public var title: String
    public var startedAt: Double
    public var endedAt: Double?
    public var status: String
    public var originPlanId: String?
    public var statsJson: String?

    enum CodingKeys: String, CodingKey {
        case id, title, status
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case originPlanId = "origin_plan_id"
        case statsJson = "stats_json"
    }

    public init(
        id: String,
        title: String,
        startedAt: Double,
        endedAt: Double? = nil,
        status: String,
        originPlanId: String? = nil,
        statsJson: String? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.originPlanId = originPlanId
        self.statsJson = statsJson
    }
}

public struct SegmentRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "segment"

    public var id: String
    public var tripId: String
    public var mode: String
    public var startedAt: Double
    public var endedAt: Double?
    public var matchedPolyline: String?

    enum CodingKeys: String, CodingKey {
        case id, mode
        case tripId = "trip_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case matchedPolyline = "matched_polyline"
    }

    public init(
        id: String,
        tripId: String,
        mode: String,
        startedAt: Double,
        endedAt: Double? = nil,
        matchedPolyline: String? = nil
    ) {
        self.id = id
        self.tripId = tripId
        self.mode = mode
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.matchedPolyline = matchedPolyline
    }
}

public struct StopRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "stop"

    public var id: String
    public var tripId: String
    public var lat: Double
    public var lon: Double
    public var arrivedAt: Double
    public var departedAt: Double?
    public var name: String?
    public var note: String?
    public var kind: String?

    enum CodingKeys: String, CodingKey {
        case id, lat, lon, name, note, kind
        case tripId = "trip_id"
        case arrivedAt = "arrived_at"
        case departedAt = "departed_at"
    }

    public init(
        id: String,
        tripId: String,
        lat: Double,
        lon: Double,
        arrivedAt: Double,
        departedAt: Double? = nil,
        name: String? = nil,
        note: String? = nil,
        kind: String? = nil
    ) {
        self.id = id
        self.tripId = tripId
        self.lat = lat
        self.lon = lon
        self.arrivedAt = arrivedAt
        self.departedAt = departedAt
        self.name = name
        self.note = note
        self.kind = kind
    }
}

extension TripRecord: Identifiable {}
extension StopRecord: Identifiable {}
extension PhotoRefRecord: Identifiable {}

public struct PhotoRefRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "photo_ref"

    public var id: String
    public var tripId: String
    public var stopId: String?
    /// PhotoKit local identifier; image bytes are NEVER copied (§3 rules).
    public var phAssetId: String
    public var takenAt: Double?
    public var lat: Double?
    public var lon: Double?
    public var isHighlight: Int

    enum CodingKeys: String, CodingKey {
        case id, lat, lon
        case tripId = "trip_id"
        case stopId = "stop_id"
        case phAssetId = "ph_asset_id"
        case takenAt = "taken_at"
        case isHighlight = "is_highlight"
    }

    public init(
        id: String,
        tripId: String,
        stopId: String?,
        phAssetId: String,
        takenAt: Double? = nil,
        lat: Double? = nil,
        lon: Double? = nil,
        isHighlight: Int = 0
    ) {
        self.id = id
        self.tripId = tripId
        self.stopId = stopId
        self.phAssetId = phAssetId
        self.takenAt = takenAt
        self.lat = lat
        self.lon = lon
        self.isHighlight = isHighlight
    }
}

/// Row mapping is hand-written (no Codable): trackpoint is the hot table —
/// a tracking day is 20–40k rows and the Phase 0 gate bulk-loads 50k — and
/// Codable record machinery is several times slower in debug builds.
public struct TrackpointRecord: Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "trackpoint"

    public var id: Int64?
    public var segmentId: String
    public var ts: Double
    public var lat: Double
    public var lon: Double
    public var hAcc: Double?
    public var speed: Double?
    public var course: Double?
    public var altitude: Double?

    public init(row: Row) {
        id = row["id"]
        segmentId = row["segment_id"]
        ts = row["ts"]
        lat = row["lat"]
        lon = row["lon"]
        hAcc = row["h_acc"]
        speed = row["speed"]
        course = row["course"]
        altitude = row["altitude"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["segment_id"] = segmentId
        container["ts"] = ts
        container["lat"] = lat
        container["lon"] = lon
        container["h_acc"] = hAcc
        container["speed"] = speed
        container["course"] = course
        container["altitude"] = altitude
    }

    /// Inserts points through one cached prepared statement — the fast path
    /// for persisting a recorded segment.
    public static func bulkInsert(_ points: [TrackpointRecord], into db: Database) throws {
        let statement = try db.cachedStatement(sql: """
            INSERT INTO trackpoint (segment_id, ts, lat, lon, h_acc, speed, course, altitude)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """)
        for point in points {
            // Fixed arity matching the SQL above; skip per-row validation.
            statement.setUncheckedArguments([
                point.segmentId, point.ts, point.lat, point.lon,
                point.hAcc, point.speed, point.course, point.altitude
            ])
            try statement.execute()
        }
    }

    public init(
        id: Int64? = nil,
        segmentId: String,
        ts: Double,
        lat: Double,
        lon: Double,
        hAcc: Double? = nil,
        speed: Double? = nil,
        course: Double? = nil,
        altitude: Double? = nil
    ) {
        self.id = id
        self.segmentId = segmentId
        self.ts = ts
        self.lat = lat
        self.lon = lon
        self.hAcc = hAcc
        self.speed = speed
        self.course = course
        self.altitude = altitude
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
