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
        /// How long **one trip's** whole routing run may take before the
        /// remaining legs are left raw (2026-08-15).
        ///
        /// `timeout_s` bounds a request; nothing bounded the trip. A 40-stop
        /// import is 39 legs, and against an endpoint that does not answer that
        /// is 39 × `timeout_s` back to back — 6½ minutes of an app that looks
        /// dead, which is what the first outside install experienced. A per-trip
        /// ceiling turns an unbounded stall into a bounded degradation: the legs
        /// that were routed keep their roads, the rest draw dashed exactly as an
        /// unroutable leg already does (PD-2), and the user is told which.
        ///
        /// Sized as "long enough that a healthy provider finishes a large trip,
        /// short enough that a broken one is a pause and not an outage".
        public let tripBudgetS: Double
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
        /// How far from a photo the reconstructor may look for a road.
        ///
        /// Deliberately **much larger than `radius_m`**, which is a GPS-accuracy
        /// floor for a dense recorded trace. A photo is almost never taken on the
        /// road: it is taken at a lookout, a car park, a beach, a restaurant —
        /// routinely hundreds of metres off. At 25 m every EXIF leg comes back
        /// `NoSegment` and nothing ever reconstructs. Being generous here is safe
        /// because `route_max_detour_ratio` is the real guard: a waypoint snapped
        /// to the wrong road inflates the route and gets rejected.
        public let routeWaypointRadiusM: Double

        enum CodingKeys: String, CodingKey {
            case baseURL = "base_url"
            case chunkSize = "chunk_size"
            case confidenceMin = "confidence_min"
            case radiusM = "radius_m"
            case timeoutS = "timeout_s"
            case tripBudgetS = "trip_budget_s"
            case displayEpsilonM = "display_epsilon_m"
            case routeMaxDetourRatio = "route_max_detour_ratio"
            case routeWaypointMinSpacingM = "route_waypoint_min_spacing_m"
            case routeWaypointRadiusM = "route_waypoint_radius_m"
        }

        public init(
            baseURL: String,
            chunkSize: Int,
            confidenceMin: Double,
            radiusM: Double,
            timeoutS: Double,
            tripBudgetS: Double,
            displayEpsilonM: Double,
            routeMaxDetourRatio: Double,
            routeWaypointMinSpacingM: Double,
            routeWaypointRadiusM: Double
        ) {
            self.baseURL = baseURL
            self.chunkSize = chunkSize
            self.confidenceMin = confidenceMin
            self.radiusM = radiusM
            self.timeoutS = timeoutS
            self.tripBudgetS = tripBudgetS
            self.displayEpsilonM = displayEpsilonM
            self.routeMaxDetourRatio = routeMaxDetourRatio
            self.routeWaypointMinSpacingM = routeWaypointMinSpacingM
            self.routeWaypointRadiusM = routeWaypointRadiusM
        }

        /// Whether this endpoint may ship in a build that leaves this Mac.
        ///
        /// Empty (matching disabled) or `https` — nothing else. A cleartext LAN
        /// host is the shape of a dogfood build pointed at a routing server on
        /// the developer's own Wi-Fi: correct on his desk, unresolvable on every
        /// other network. The failure that produces is not a film without roads,
        /// it is a stall — `matchTrip` awaits legs one after another at
        /// `timeout_s` each, so the more photographs a trip has the longer the
        /// app appears dead (the 2026-08-15 P0, first outside install).
        ///
        /// Read only by the release guard in `AppConfig.loadOrDie`; a debug run
        /// against `http://192.168.x.x` is the whole point of device testing and
        /// stays legal.
        public var isDistributableEndpoint: Bool {
            guard !baseURL.isEmpty else { return true }
            return URL(string: baseURL)?.scheme?.lowercased() == "https"
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
                tripBudgetS: tripBudgetS,
                displayEpsilonM: displayEpsilonM,
                routeMaxDetourRatio: routeMaxDetourRatio,
                routeWaypointMinSpacingM: routeWaypointMinSpacingM,
                routeWaypointRadiusM: routeWaypointRadiusM
            )
        }
    }
}
