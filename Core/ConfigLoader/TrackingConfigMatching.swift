import Foundation

/// The §4.4 road-reconstruction block, split out of `TrackingConfig.swift` to
/// keep both files inside the size budget. Two providers read it: the `/match`
/// map-matcher for dense recorded traces, and the `/route` reconstructor for
/// sparse photo-EXIF legs (typed-leg pass 2026-07-26).
public extension TrackingConfig {
    /// Sendable: the OSRM providers carry this across their async transport.
    struct Matching: Decodable, Equatable, Sendable {
        /// OSRM host for map matching (§4.4), e.g. "http://127.0.0.1:5000".
        /// Empty string = matching disabled: segments keep raw geometry and
        /// readers fall back to the simplified raw polyline. Stays empty
        /// until the self-hosted server exists (`Docs/osrm-setup.md`).
        public let baseURL: String
        /// Max trackpoints per /match request (spec §4.4: ≤100).
        public let chunkSize: Int
        /// A segment whose worst per-matching confidence is below this keeps
        /// its raw polyline (spec §4.4: render "inferred", never invent roads).
        public let confidenceMin: Double
        /// Floor for the per-point search radius sent to OSRM; a point's own
        /// h_acc is used when it is larger.
        public let radiusM: Double
        /// Per-request timeout. Matching is best-effort and must never block
        /// trip completion (§4.4), so this stays short.
        public let timeoutS: Double
        /// Douglas-Peucker ε for *matched* geometry in the recap. Tighter
        /// than simplify.epsilon_m: 15 m would visibly cut snapped corners
        /// at recap zoom, but raw OSRM output on a long trip would blow the
        /// §4.5 render budget.
        public let displayEpsilonM: Double
        /// Sanity gate for a *reconstructed* (`/route`) leg, which — unlike
        /// `/match` — returns no confidence of its own. The routed distance may
        /// exceed the straight line through the waypoints by at most this
        /// factor; beyond it the "road" is a detour the photos never evidenced
        /// (one bad EXIF fix dragging the route across a bay), and the leg keeps
        /// its raw geometry and renders inferred (PD-2/PD-3).
        public let routeMaxDetourRatio: Double
        /// Intermediate photo waypoints closer than this to the previously kept
        /// one are dropped before routing: EXIF positions cluster, and a
        /// via-waypoint pair metres apart pins the route to whichever side of
        /// the road the noise landed on, sometimes forcing a U-turn.
        public let routeWaypointMinSpacingM: Double

        enum CodingKeys: String, CodingKey {
            case baseURL = "base_url"
            case chunkSize = "chunk_size"
            case confidenceMin = "confidence_min"
            case radiusM = "radius_m"
            case timeoutS = "timeout_s"
            case displayEpsilonM = "display_epsilon_m"
            case routeMaxDetourRatio = "route_max_detour_ratio"
            case routeWaypointMinSpacingM = "route_waypoint_min_spacing_m"
        }

        public init(
            baseURL: String,
            chunkSize: Int,
            confidenceMin: Double,
            radiusM: Double,
            timeoutS: Double,
            displayEpsilonM: Double,
            routeMaxDetourRatio: Double,
            routeWaypointMinSpacingM: Double
        ) {
            self.baseURL = baseURL
            self.chunkSize = chunkSize
            self.confidenceMin = confidenceMin
            self.radiusM = radiusM
            self.timeoutS = timeoutS
            self.displayEpsilonM = displayEpsilonM
            self.routeMaxDetourRatio = routeMaxDetourRatio
            self.routeWaypointMinSpacingM = routeWaypointMinSpacingM
        }

        /// The shipped tunables pointed at a different server — a stub
        /// transport's placeholder host in tests, or a dogfood instance. Keeps
        /// `TrackingConfig.json` the single source for every other value
        /// (§0 rule 2) instead of re-listing them at each call site.
        public func withBaseURL(_ baseURL: String) -> Matching {
            Matching(
                baseURL: baseURL,
                chunkSize: chunkSize,
                confidenceMin: confidenceMin,
                radiusM: radiusM,
                timeoutS: timeoutS,
                displayEpsilonM: displayEpsilonM,
                routeMaxDetourRatio: routeMaxDetourRatio,
                routeWaypointMinSpacingM: routeWaypointMinSpacingM
            )
        }
    }
}
