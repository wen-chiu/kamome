import Foundation
import KamomeConfig
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

    public init(distanceM: Double, driveS: Double, walkS: Double, stopCount: Int, topSpeedKmh: Double) {
        self.distanceM = distanceM
        self.driveS = driveS
        self.walkS = walkS
        self.stopCount = stopCount
        self.topSpeedKmh = topSpeedKmh
    }

    public static func compute(
        segments: [TrackingEngine.Segment],
        stops: [TrackingEngine.Stop],
        config: TrackingConfig
    ) -> TripStats {
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
                    distance += Geo.distanceM(latA: previous.lat, lonA: previous.lon, latB: point.lat, lonB: point.lon)
                }
                previous = point
            }
            topMps = max(topMps, maxWindowSpeedMps(points: segment.points, config: config))
        }

        return TripStats(
            distanceM: distance,
            driveS: drive,
            walkS: walk,
            stopCount: stops.count,
            topSpeedKmh: topMps * 3.6
        )
    }

    /// Top speed per ADR 2026-07-12: displacement over the trailing
    /// `speed_smoothing_window_s`, never per-fix values — position glitches
    /// leak into CoreLocation's own speed field (137 m/s on the 2026-07-18
    /// drive), so raw OS speeds are as noise-prone as adjacent-fix deltas.
    /// Points worse than `filter.speed_max_h_acc_m` are not speed evidence;
    /// like the engine, a window under ⅓ full contributes nothing.
    private static func maxWindowSpeedMps(points: [LocationSample], config: TrackingConfig) -> Double {
        let windowS = config.segmentation.speedSmoothingWindowS
        let usable = points.filter { point in
            guard let hAcc = point.hAccM else { return true }  // missing metadata ≠ bad fix
            return hAcc <= config.filter.speedMaxHAccM
        }
        var best = 0.0
        var oldest = 0
        for index in usable.indices.dropFirst() {
            while usable[index].ts - usable[oldest].ts > windowS, oldest < index - 1 {
                oldest += 1
            }
            let dt = usable[index].ts - usable[oldest].ts
            guard dt >= windowS / 3 else { continue }
            let meters = Geo.distanceM(
                latA: usable[oldest].lat, lonA: usable[oldest].lon,
                latB: usable[index].lat, lonB: usable[index].lon
            )
            best = max(best, meters / dt)
        }
        return best
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
