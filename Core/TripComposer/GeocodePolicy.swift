import Foundation
import KamomeConfig

/// Cache + throttle policy for reverse geocoding (§4.2: "throttled, cached").
/// Pure bookkeeping — CLGeocoder itself lives in the app layer.
public struct GeocodePolicy {
    public enum Decision: Equatable {
        case cached(String)
        case lookup
        case throttled(retryAfterS: Double)
    }

    private var cache: [String: String] = [:]
    private var lastLookupAt: Double?
    private let config: TrackingConfig.Geocode

    public init(config: TrackingConfig.Geocode) {
        self.config = config
    }

    public func decision(lat: Double, lon: Double, now: Double) -> Decision {
        if let name = cache[key(lat: lat, lon: lon)] {
            return .cached(name)
        }
        if let last = lastLookupAt, now - last < config.minIntervalS {
            return .throttled(retryAfterS: config.minIntervalS - (now - last))
        }
        return .lookup
    }

    public mutating func recordLookup(lat: Double, lon: Double, name: String, at now: Double) {
        cache[key(lat: lat, lon: lon)] = name
        lastLookupAt = now
    }

    private func key(lat: Double, lon: Double) -> String {
        let precision = config.cachePrecisionDeg
        let roundedLat = (lat / precision).rounded() * precision
        let roundedLon = (lon / precision).rounded() * precision
        return String(format: "%.4f,%.4f", roundedLat, roundedLon)
    }
}
