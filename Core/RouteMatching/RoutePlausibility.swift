import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// Waypoint hygiene for route reconstruction — **provider-independent by
/// design** (2026-08-20).
///
/// These lived as statics on `OSRMRouteProvider` until the Geoapify migration,
/// which is exactly the accident the 2026-08-16 ADR predicted: they read like
/// OSRM plumbing, they are Kamome policy, and a new provider file would have
/// silently shipped without them. Nothing here knows what an OSRM or a Geoapify
/// URL looks like.
enum RouteWaypoints {
    /// Drops intermediate waypoints that sit within `minSpacingM` of the last
    /// kept one, then caps the list at the provider's per-request location limit
    /// by keeping an evenly spread subset. The **endpoints are never dropped** —
    /// they are the stop centroids the leg is defined by; only the photo
    /// evidence in between is thinned.
    static func thinned(_ waypoints: [RouteMatchPoint], minSpacingM: Double, limit: Int) -> [RouteMatchPoint] {
        guard waypoints.count > 2 else { return waypoints }
        let first = waypoints[0]
        let last = waypoints[waypoints.count - 1]

        var kept: [RouteMatchPoint] = [first]
        for waypoint in waypoints[1..<(waypoints.count - 1)] {
            let previous = kept[kept.count - 1]
            let spacing = Geo.distanceM(latA: previous.lat, lonA: previous.lon, latB: waypoint.lat, lonB: waypoint.lon)
            if spacing >= minSpacingM { kept.append(waypoint) }
        }
        kept.append(last)

        guard limit >= 2, kept.count > limit else { return kept }
        // Evenly spread: keep both ends and sample the interior.
        let interiorBudget = limit - 2
        let interior = kept[1..<(kept.count - 1)]
        let stride = Double(interior.count) / Double(max(interiorBudget, 1))
        var capped: [RouteMatchPoint] = [kept[0]]
        for slot in 0..<interiorBudget {
            let index = Int((Double(slot) + 0.5) * stride)
            capped.append(interior[interior.startIndex + min(index, interior.count - 1)])
        }
        capped.append(kept[kept.count - 1])
        return capped
    }

    /// Total great-circle length through the waypoints — the floor any honest
    /// road route must be at least as long as.
    static func straightLineM(_ waypoints: [RouteMatchPoint]) -> Double {
        zip(waypoints, waypoints.dropFirst()).reduce(0.0) { sum, pair in
            sum + Geo.distanceM(latA: pair.0.lat, lonA: pair.0.lon, latB: pair.1.lat, lonB: pair.1.lon)
        }
    }
}

/// The PD-3 sanity gate on a reconstructed leg: a routing endpoint always
/// answers *something* drivable, so without this one bad EXIF fix silently
/// produces a confident 300 km detour drawn as real road.
///
/// **What this gate is, and what it is not** (measured 2026-08-20, ADR (d)).
/// It is outlier protection against a waypoint that is plainly wrong. It is
/// **not** a wrong-road detector, and it was never able to be one: on the
/// Geysir–Gullfoss leg, routes through displaced waypoints measured 1.92–2.31×
/// while snapping only 44–132 m from a road, and legitimate fjord and peninsula
/// drives are themselves 2–4×. A ratio cannot separate a wrong road from an
/// indirect one, so `route_max_detour_ratio` stays where it was set (2.5) rather
/// than being tightened into a job it cannot do.
///
/// The class the gate genuinely does not cover — a waypoint with no road
/// anywhere near it, a beach or a lagoon or open sea — is refused by the
/// provider itself before a route exists.
enum RoutePlausibility {
    /// Whether a routed distance is believable for these waypoints, logging the
    /// rejection where it happens. The log line lives with the policy rather
    /// than in a provider so the next provider cannot lose it.
    static func acceptsRoute(
        distanceM: Double,
        through waypoints: [RouteMatchPoint],
        maxDetourRatio: Double
    ) -> Bool {
        let straightM = RouteWaypoints.straightLineM(waypoints)
        // A zero-length straight line means every waypoint collapsed onto one
        // point; there is no ratio to take and nothing worth drawing.
        guard straightM > 0 else { return false }
        guard distanceM <= straightM * maxDetourRatio else {
            KamomeLog.routing.notice("""
                route: REJECTED by the detour gate — \(distanceM / 1000, format: .fixed(precision: 1)) km routed \
                vs \(straightM / 1000, format: .fixed(precision: 1)) km straight \
                (\(distanceM / straightM, format: .fixed(precision: 1))× > \
                \(maxDetourRatio, format: .fixed(precision: 1))×) — leg stays raw (PD-3)
                """)
            return false
        }
        return true
    }
}
