import Foundation

/// One trackpoint as matching input. Plain values so callers can feed
/// persistence records, replay fixtures, or imported points (§4.7) alike.
public struct RouteMatchPoint: Equatable, Sendable {
    public let ts: Double
    public let lat: Double
    public let lon: Double
    /// Horizontal accuracy in meters, if known — becomes the per-point
    /// search radius (floored by `matching.radius_m`).
    public let hAccM: Double?

    public init(ts: Double, lat: Double, lon: Double, hAccM: Double? = nil) {
        self.ts = ts
        self.lat = lat
        self.lon = lon
        self.hAccM = hAccM
    }
}

/// A confident snap of one segment's trace onto the road network.
public struct RouteMatchOutcome: Equatable, Sendable {
    /// Road-following geometry, in trace order.
    public let geometry: [GeoPoint]
    /// Worst per-matching confidence that survived (0…1).
    public let confidence: Double

    public init(geometry: [GeoPoint], confidence: Double) {
        self.geometry = geometry
        self.confidence = confidence
    }

    /// The `segment.matched_polyline` storage form.
    public var encodedPolyline: String {
        EncodedPolyline.encode(geometry)
    }
}

/// Boundary for map matching (§4.4) — the same one-file-per-backend
/// discipline as `RecapSnapshotProviding` (§0 boundary rule): OSRM types
/// stay inside `OSRMMatchProvider.swift`, and future backends (e.g. a foot
/// profile for walk segments) conform here without touching callers.
///
/// Returns nil when no confident match exists (server disabled, trace too
/// short, confidence below the floor) — the caller keeps raw geometry.
/// Throws only for transport-level failures; callers treat both the same
/// way (fall back, never block — §4.4) but may log errors.
public protocol RouteMatchProviding: Sendable {
    func match(_ points: [RouteMatchPoint]) async throws -> RouteMatchOutcome?
}
