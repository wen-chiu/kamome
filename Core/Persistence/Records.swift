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

public struct TrackpointRecord: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
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

    enum CodingKeys: String, CodingKey {
        case id, ts, lat, lon, speed, course, altitude
        case segmentId = "segment_id"
        case hAcc = "h_acc"
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
