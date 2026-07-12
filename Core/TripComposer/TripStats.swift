import Foundation
import KamomeTrackingEngine

/// Denormalized per-trip stats for `trip.stats_json` (§3) and the S3 stats
/// strip. Computed once at trip completion.
public struct TripStats: Codable, Equatable {
    public let distanceM: Double
    public let driveS: Double
    public let walkS: Double
    public let stopCount: Int
    /// km/h, from per-point speeds where present, else per-step displacement.
    public let topSpeedKmh: Double

    enum CodingKeys: String, CodingKey {
        case distanceM = "distance_m"
        case driveS = "drive_s"
        case walkS = "walk_s"
        case stopCount = "stop_count"
        case topSpeedKmh = "top_speed_kmh"
    }

    public static func compute(segments: [TrackingEngine.Segment], stops: [TrackingEngine.Stop]) -> TripStats {
        var distance = 0.0
        var drive = 0.0
        var walk = 0.0
        var topMps = 0.0

        for segment in segments {
            let duration = (segment.endedAt ?? segment.startedAt) - segment.startedAt
            switch segment.mode {
            case .drive, .scooter, .transit: drive += duration
            case .walk, .cycle: walk += duration
            case .unknown: break
            }
            var previous: LocationSample?
            for point in segment.points {
                if let previous {
                    let step = Geo.distanceM(latA: previous.lat, lonA: previous.lon, latB: point.lat, lonB: point.lon)
                    distance += step
                    let dt = point.ts - previous.ts
                    if let osSpeed = point.speedMps {
                        topMps = max(topMps, osSpeed)
                    } else if dt > 0 {
                        topMps = max(topMps, step / dt)
                    }
                }
                previous = point
            }
        }

        return TripStats(
            distanceM: distance,
            driveS: drive,
            walkS: walk,
            stopCount: stops.count,
            topSpeedKmh: topMps * 3.6
        )
    }

    public func jsonString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func from(jsonString: String?) -> TripStats? {
        guard let jsonString, let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TripStats.self, from: data)
    }
}
