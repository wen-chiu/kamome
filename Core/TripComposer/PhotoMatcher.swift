import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// §4.3 photo→stop assignment. Pure logic; PhotoKit stays in the app layer.
public enum PhotoMatcher {
    /// What the matcher needs to know about one photo.
    public struct Photo: Equatable {
        public let id: String        // PHAsset local identifier
        public let takenAt: Double?  // unix epoch
        public let lat: Double?
        public let lon: Double?

        public init(id: String, takenAt: Double?, lat: Double? = nil, lon: Double? = nil) {
            self.id = id
            self.takenAt = takenAt
            self.lat = lat
            self.lon = lon
        }
    }

    public struct Stop: Equatable {
        public let id: String
        public let lat: Double
        public let lon: Double
        public let arrivedAt: Double
        public let departedAt: Double?

        public init(id: String, lat: Double, lon: Double, arrivedAt: Double, departedAt: Double?) {
            self.id = id
            self.lat = lat
            self.lon = lon
            self.arrivedAt = arrivedAt
            self.departedAt = departedAt
        }
    }

    /// nil = route-attached (photo_ref.stop_id stays NULL).
    ///
    /// Rules in order (§4.3): GPS → nearest stop within `match_radius_m`;
    /// else timestamp → the stop whose [arrived, departed] contains it;
    /// else route-attached. GPS outranks timestamp on conflict.
    public static func stopId(
        for photo: Photo,
        stops: [Stop],
        tripEndedAt: Double,
        config: TrackingConfig.Photos
    ) -> String? {
        if let lat = photo.lat, let lon = photo.lon {
            let nearest = stops
                .map { (stop: $0, distance: Geo.distanceM(latA: lat, lonA: lon, latB: $0.lat, lonB: $0.lon)) }
                .min { $0.distance < $1.distance }
            if let nearest, nearest.distance <= config.matchRadiusM {
                return nearest.stop.id
            }
            // GPS says "not at any stop" — that is an answer, not a fallback:
            // a geotagged photo taken mid-drive is route-attached even if its
            // timestamp falls inside a stop interval (clock skew, camera roll
            // imports).
            return nil
        }
        if let takenAt = photo.takenAt {
            return stops.first {
                takenAt >= $0.arrivedAt && takenAt <= ($0.departedAt ?? tripEndedAt)
            }?.id
        }
        return nil
    }
}
