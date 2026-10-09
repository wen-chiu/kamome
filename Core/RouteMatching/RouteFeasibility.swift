import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// **Could this road have been the way the leg was travelled?** (ADR 2026-10-03).
///
/// The detour gate (`RoutePlausibility`) asks whether a route's *shape* is
/// believable, and nothing else. Across connected land that is not enough: a
/// flight between two airports on one continent comes back from the router as
/// a real road a little longer than the straight line, passes the gate at
/// 1.4×, and was stored as `road` — the film then drew a drive nobody drove
/// (Chiu's device trip, 2026-10-03). `LegPace` cannot
/// catch it whenever the photographs either side of the flight are a night
/// apart, and routing never answers "no road" where a road exists.
///
/// Two questions the shape cannot answer, asked of the road the router chose:
///
/// - **Time.** The *routed* distance over the leg's elapsed time, padded by
///   `LegPace`'s clock allowance (the time zones the longitudes allow, plus
///   `crossing_pace_clock_margin_s`). At or above
///   `crossing_route_pace_min_kmh` nobody drove it: it is a crossing. Routed
///   rather than straight-line distance, so a lower ceiling than `LegPace`'s
///   is as safe — and catches flights with far longer gaps either side.
/// - **Witness.** The time test is only as good as the photographs at the two
///   ends; one taken the evening before a flight and the next a day after
///   landing defeats it. So, independent of any clock: a stretch of the route
///   longer than a day's driving (`route_unwitnessed_max_m`, 1,200 km) with
///   no photograph along it is not
///   evidence of a drive. It is not proof of a flight either, so it is not a
///   crossing — it is refused as road and drawn dashed, which is the honest
///   reading of "we do not know" (PD-1).
///
/// Distances and durations are logged, never a coordinate (§0).
public enum RouteFeasibility {
    public enum Verdict: Equatable, Sendable {
        /// The route could have been driven in the time, and photographs
        /// witness it often enough: store it as road.
        case drivable
        /// No drive covers this road in the time the photographs allow: a
        /// crossing (`beyond_driving`).
        case notDriven
        /// A stretch longer than a day's driving with no photograph on it:
        /// refused as road (`implausible_route`), never a crossing.
        case unwitnessed
    }

    /// `route` is the road the provider returned; `trace` is **every** photo
    /// position of the leg in time order — not the thinned waypoints, since
    /// thinning is exactly what would erase a witness.
    public static func judge(
        route: [GeoPoint], trace: [RouteMatchPoint], config: TrackingConfig.Matching
    ) -> Verdict {
        guard route.count >= 2, let first = trace.first, let last = trace.last, trace.count >= 2 else {
            return .drivable
        }
        let routedM = lengthM(route)
        let elapsedS = max(0, last.ts - first.ts)
        let allowanceS = LegPace.clockAllowanceS(from: first, to: last, config: config)
        let paceKmh = (routedM / 1000) / ((elapsedS + allowanceS) / 3600)
        let unwitnessedM = longestUnwitnessedM(routedM: routedM, trace: trace)

        let notDriven = routedM >= config.crossingPaceMinDistanceM
            && config.crossingRoutePaceMinKmh > 0
            && paceKmh >= config.crossingRoutePaceMinKmh
        let dayOfDrivingM = config.routeUnwitnessedMaxM
        let unwitnessed = dayOfDrivingM > 0 && unwitnessedM > dayOfDrivingM
        let verdict: Verdict = notDriven ? .notDriven : (unwitnessed ? .unwitnessed : .drivable)

        // The diagnostic a long leg was missing: which of the two tests decided,
        // and by how much. Only legs long enough for either test to matter.
        if routedM >= config.crossingPaceMinDistanceM {
            KamomeLog.routing.notice("""
                route: feasibility — \(routedM / 1000, format: .fixed(precision: 0)) km of road, \
                \(elapsedS / 3600, format: .fixed(precision: 1)) h between photographs \
                (+\(allowanceS / 3600, format: .fixed(precision: 1)) h clock allowance) = \
                \(paceKmh, format: .fixed(precision: 0)) km/h vs \
                \(config.crossingRoutePaceMinKmh, format: .fixed(precision: 0)); longest stretch with no \
                photograph \(unwitnessedM / 1000, format: .fixed(precision: 0)) km vs a day's driving \
                \(dayOfDrivingM / 1000, format: .fixed(precision: 0)) km → \(String(describing: verdict), privacy: .public)
                """)
        }
        return verdict
    }

    /// Length of the route the provider drew.
    static func lengthM(_ route: [GeoPoint]) -> Double {
        zip(route, route.dropFirst()).reduce(0.0) { sum, pair in
            sum + Geo.distanceM(latA: pair.0.lat, lonA: pair.0.lon, latB: pair.1.lat, lonB: pair.1.lon)
        }
    }

    /// **The longest stretch of the road with no photograph along it.**
    ///
    /// The route is shared between consecutive photographs in proportion to
    /// the straight line between them — exact when the detour is even along
    /// the leg, and an estimate otherwise (INFERRED: the provider's per-pair
    /// parts would be exact, and are not carried past the `RouteProvider`
    /// boundary, which this deliberately does not change). A leg whose
    /// photographs all sit on one spot has nothing to share by, so the whole
    /// route is one unwitnessed stretch.
    static func longestUnwitnessedM(routedM: Double, trace: [RouteMatchPoint]) -> Double {
        let straight = zip(trace, trace.dropFirst()).map { pair in
            Geo.distanceM(latA: pair.0.lat, lonA: pair.0.lon, latB: pair.1.lat, lonB: pair.1.lon)
        }
        let total = straight.reduce(0, +)
        guard total > 0, let longest = straight.max() else { return routedM }
        return routedM * longest / total
    }
}
