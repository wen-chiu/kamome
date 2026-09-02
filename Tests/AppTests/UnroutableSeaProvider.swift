import KamomeRouteMatching

/// **A routing provider that knows where the sea is** — the offline stand-in for
/// Geoapify's `400 No suitable edges near location`.
///
/// **Why a stub is the only option here, and why it is honest.** The gates run
/// with `matching.base_url` empty, which is the shipped default and the worst
/// case for the camera: every leg keeps raw geometry. But "routing is switched
/// off" establishes *nothing*, and a crossing is precisely a leg something was
/// established about — `SegmentRoutability` refuses to read NULL as "there is no
/// road here", which is the whole point of it. So a fixture cannot contain a
/// crossing unless some provider answers.
///
/// This answers the way the real one does, and the geography is stated rather
/// than inferred: a leg whose two ends lie on opposite sides of `meridian` has
/// open sea between them and no road. Everything else answers
/// `.notEstablished(.routingDisabled)` — bit for bit what the offline gate gets
/// today, so every non-crossing leg of every fixture is unaffected.
///
/// **Deliberately not a distance rule.** A threshold here would quietly make the
/// gate agree with the design's own worst failure mode: `act_split_km` fires 20
/// times on the Iceland dump and every one of those gaps is a photograph gap
/// inside a drive (`Docs/camera-arcs.md` §0). A stub that flew them would prove
/// the arc works on cases that must never produce one.
struct UnroutableSeaProvider: RouteReconstructing {
    /// The one committed fixture with a leg that has no road under it (authored
    /// 2026-08-30). Measured that day: **no fixture in the tree contained a
    /// crossing** — the real Miyakojima dump has a 20.0 km largest gap and zero
    /// discontinuities — so nothing the camera design exists for had ever been
    /// gated or judged.
    static let crossingFixture = "ishigaki-crossing"

    /// The **long-haul** type-2 fixture (authored 2026-09-02): Taipei → Auckland,
    /// 8,732 km and 53.2 degrees of longitude against Ishigaki's 272 km and 2.6.
    ///
    /// Two of them, deliberately. `crossing_beat_s` is one number for every
    /// crossing, and a beat that suits a 272 km hop makes the aircraft tear across
    /// an 8,732 km frame — so the film that judges it has to exist at both scales
    /// or the constant is reverse-derived from one trip, which is how
    /// `body_span_padding` and `tier_skip_share` were both built and both removed.
    static let longHaulFixture = "auckland-crossing"

    /// Where the sea is, per fixture: between Taiwan and the Yaeyama islands for
    /// one, and out in the Pacific for the other. Every other committed fixture
    /// sits entirely on one side of whichever meridian it would be given, so they
    /// are untouched whether or not this provider is used.
    static let seaMeridian = 122.5
    static let pacificMeridian = 150.0

    /// The provider a fixture should be routed with **offline**. Named here so
    /// the continuity gate and the review-render harness cannot answer the
    /// question differently — the mistake `ReviewSubstrate` was created to stop.
    static func forFixture(_ fixture: String) -> UnroutableSeaProvider? {
        switch fixture {
        case crossingFixture: return UnroutableSeaProvider(meridian: seaMeridian)
        case longHaulFixture: return UnroutableSeaProvider(meridian: pacificMeridian)
        default: return nil
        }
    }

    /// The longitude the water runs along. A leg with ends either side of it is
    /// a crossing; a leg entirely on one side is land.
    let meridian: Double

    func route(_ waypoints: [RouteMatchPoint]) async throws -> RouteReconstruction {
        guard let first = waypoints.first, let last = waypoints.last else {
            return .notEstablished(.tooFewWaypoints)
        }
        guard (first.lon < meridian) != (last.lon < meridian) else {
            return .notEstablished(.routingDisabled)
        }
        return .noRoadHere
    }
}
