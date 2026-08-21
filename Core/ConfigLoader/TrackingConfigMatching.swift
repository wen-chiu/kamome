import Foundation

/// The §4.4 road-reconstruction block, split out of `TrackingConfig.swift` to
/// keep both files inside the size budget. Two providers read it: the `/match`
/// map-matcher for dense recorded traces, and the `/route` reconstructor for
/// sparse photo-EXIF legs (typed-leg pass 2026-07-26).
public extension TrackingConfig {
    /// Sendable: the OSRM providers carry this across their async transport.
    struct Matching: Decodable, Equatable, Sendable {
        /// Routing endpoint (§4.4), e.g. "https://api.geoapify.com" — or, from
        /// the pre-launch Cloudflare Worker onwards, the Worker that holds the
        /// key (`Docs/pre-launch.md`). Empty string = routing disabled:
        /// segments keep raw geometry and readers fall back to the simplified
        /// raw polyline. **Ships empty**, so a fresh checkout and CI contact
        /// nothing; a build that routes sets it locally.
        ///
        /// `private(set) var` only so `withBaseURL` can copy-and-replace
        /// without going through the memberwise initialiser, which is what
        /// silently dropped `apiKey` until 2026-08-20.
        public private(set) var baseURL: String
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
        /// How far from a photo a reconstructor may look for a road.
        ///
        /// ⚠️ **Nothing reads this today** (2026-08-20). It was OSRM's
        /// `radiuses=` parameter, and Geoapify's `/v1/routing` has no equivalent
        /// — measured behaviourally, since unknown parameters are silently
        /// ignored rather than refused. It is kept rather than deleted for two
        /// reasons: the class it genuinely guarded (a waypoint with no road
        /// anywhere near it — a beach, a lagoon, open sea) is now refused by the
        /// provider itself with `400 No suitable edges near location`, so no
        /// behaviour was lost; and `/v1/mapmatching` *does* report a per-point
        /// `match_distance`, which is where this value plausibly finds its next
        /// reader when Capture Beta opens.
        ///
        /// It was never the wrong-road guard the migration briefing believed it
        /// to be — `Docs/decisions.md` 2026-08-20 (d) has the measurements.
        public let routeWaypointRadiusM: Double

        /// The routing provider's API key — **deliberately not a JSON key.**
        ///
        /// `TrackingConfig.json` is committed and bundled, so a secret in it is a
        /// secret in git; `Docs/handoff-P3.5.md` has forbidden that since the VPS
        /// token was first discussed. This value is absent from `CodingKeys` and
        /// defaults to empty, so the file cannot carry it even by accident: it is
        /// supplied at load time from the app bundle (`AppConfig`), which reads it
        /// from an `Info.plist` entry fed by a gitignored `.xcconfig`.
        ///
        /// Empty is a normal state, not a failure — a checkout with no
        /// `Secrets.xcconfig` runs with routing disabled.
        public private(set) var apiKey: String = ""

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

        /// The shipped tunables carrying a key the config file never held.
        /// Mirrors `withBaseURL`: `TrackingConfig.json` stays the single source
        /// for every value that is safe to commit, and the one that is not
        /// arrives here.
        public func withAPIKey(_ key: String) -> Matching {
            var copy = self
            copy.apiKey = key
            return copy
        }

        /// The shipped tunables pointed at a different server — a stub
        /// transport's placeholder host in tests, or a dogfood instance. Keeps
        /// `TrackingConfig.json` the single source for every other value
        /// (§0 rule 2) instead of re-listing them at each call site.
        ///
        /// **Including the key** (fixed 2026-08-20). This rebuilt the struct
        /// through the memberwise initialiser, where `apiKey` is not a
        /// parameter, so it silently reset to empty. Nothing noticed while no
        /// request carried a key; the moment one did, every desk render harness
        /// — all of which reach the provider through `withBaseURL` — would have
        /// sent keyless requests and got 401 back as "the provider is
        /// unreachable".
        public func withBaseURL(_ baseURL: String) -> Matching {
            var copy = self
            copy.baseURL = baseURL
            return copy
        }
    }
}
