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

/// Why a provider could not answer — thrown, never returned, because none of
/// these is a verdict about the geography (2026-08-15).
///
/// **The distinction that matters, and why it is being drawn now.** A leg with
/// no road geometry draws dashed, and until now every reason produced that same
/// dashed leg with nothing to tell them apart: a ferry crossing that genuinely
/// has no road route looked exactly like a server on the wrong Wi-Fi. That was
/// survivable against a routing box on the developer's LAN, which either
/// answered or did not. A hosted provider adds cold starts, quotas and outages —
/// failures that are *temporary*, and where the honest thing to tell the user is
/// "try again", not "there is no road here".
///
/// So: a nil `RouteMatchOutcome` means the provider answered and the answer was
/// "no plausible route" — permanent, correct, dashed forever. One of these means
/// nobody answered — retryable, and never the geography's fault.
public enum RouteProviderFailure: Error, Equatable, Sendable {
    /// Nothing answered: DNS, ATS, a LAN address on someone else's network, a
    /// dropped connection, a timeout, a cold start that outran `timeout_s`.
    case unreachable(String)
    /// Refused for load — HTTP 429, or a quota response. `retryAfterS` is the
    /// server's own advice when it gave any.
    case rateLimited(retryAfterS: Double?)
    /// Answered, with a status that is neither success nor an OSRM verdict.
    case refused(status: Int)
}

/// Boundary for map matching (§4.4) — the same one-file-per-backend
/// discipline as `MapRenderer` (§0 boundary rule): OSRM types
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
