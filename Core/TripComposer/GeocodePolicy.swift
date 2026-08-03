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
        recordAttempt(at: now)
    }

    /// Marks that a lookup was *made*, whether or not it produced a name.
    ///
    /// **The throttle has to charge for failures too** (2026-08-03). It used to
    /// advance only on success, so one empty or errored reverse-geocode left the
    /// clock where it was and the very next stop fired immediately. CLGeocoder
    /// rate-limits per app, so that turns a single transient failure into a burst
    /// against a service that is already refusing — and every remaining stop in
    /// the queue fails with it. It reads on screen as "the first few stops are
    /// named and the rest say Unnamed stop".
    public mutating func recordAttempt(at now: Double) {
        lastLookupAt = now
    }

    private func key(lat: Double, lon: Double) -> String {
        let precision = config.cachePrecisionDeg
        let roundedLat = (lat / precision).rounded() * precision
        let roundedLon = (lon / precision).rounded() * precision
        return String(format: "%.4f,%.4f", roundedLat, roundedLon)
    }
}
