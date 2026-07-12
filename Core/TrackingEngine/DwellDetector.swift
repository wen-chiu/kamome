import Foundation
import KamomeConfig

/// §4.2 sliding-window stop detection: if every point of the last
/// `dwell.window_s` fits within `dwell.radius_m` of the window centroid,
/// the traveler has stopped.
struct DwellDetector {
    struct Dwell {
        let centerLat: Double
        let centerLon: Double
        /// Timestamp of the oldest window point — the stop's arrival time.
        let sinceTs: Double
    }

    private struct Fix {
        let ts: Double
        let lat: Double
        let lon: Double
    }

    private var window: [Fix] = []
    private let config: TrackingConfig.Dwell

    init(config: TrackingConfig.Dwell) {
        self.config = config
    }

    mutating func add(ts: Double, lat: Double, lon: Double) -> Dwell? {
        window.append(Fix(ts: ts, lat: lat, lon: lon))
        window.removeAll { $0.ts < ts - config.windowS }

        // The window must actually span the full duration before it can vote.
        guard let oldest = window.first, ts - oldest.ts >= config.windowS - 1 else { return nil }

        let centerLat = window.reduce(0) { $0 + $1.lat } / Double(window.count)
        let centerLon = window.reduce(0) { $0 + $1.lon } / Double(window.count)
        let allInside = window.allSatisfy {
            Geo.distanceM(latA: $0.lat, lonA: $0.lon, latB: centerLat, lonB: centerLon) <= config.radiusM
        }
        guard allInside else { return nil }
        return Dwell(centerLat: centerLat, centerLon: centerLon, sinceTs: oldest.ts)
    }

    mutating func reset() {
        window.removeAll()
    }
}
