import KamomeConfig
@testable import KamomeRouteMatching
import XCTest

/// Route **reconstruction** for sparse photo-EXIF legs — Geoapify
/// `/v1/routing` since the 2026-08-20 migration, and the Kamome policies that
/// travel with it rather than with any one provider.
///
/// Split out of `RouteMatchingTests` when the migration pushed that file past
/// its length budget; the map-matching half stayed there.
final class RouteReconstructionTests: XCTestCase {
    private let matchingConfig = TrackingConfig.Matching(
        baseURL: "https://routing.invalid",
        chunkSize: 100,
        confidenceMin: 0.5,
        radiusM: 25,
        timeoutS: 10,
        tripBudgetS: 60,
        displayEpsilonM: 5,
        routeMaxDetourRatio: 2.5,
        routeWaypointMinSpacingM: 250,
        routeWaypointRadiusM: 500
    )

    // MARK: - Route reconstruction (sparse EXIF legs, Geoapify /v1/routing)
    //
    // Migrated from OSRM on 2026-08-20 (`Docs/decisions.md`). Every rule the
    // OSRM tests held is restated here against the new wire format; the one
    // assertion that is *gone* rather than restated is `radiuses=`, because the
    // parameter does not exist on this provider and ADR (d) establishes that
    // nothing was lost with it — the class it guarded is refused natively as
    // `400 No suitable edges near location`, which is asserted below.

    /// The provider under test, keyed. `withBaseURL` is applied **last** on
    /// purpose: that order used to drop the key (fixed 2026-08-20), and this is
    /// where a regression would show up as a keyless request.
    private var routingConfig: TrackingConfig.Matching {
        matchingConfig.withAPIKey("test-key").withBaseURL("https://routing.invalid")
    }

    /// One GeoJSON route, as measured: metres, and one `MultiLineString` part
    /// per waypoint pair.
    private func routeBody(distanceM: Double, parts: [[GeoPoint]]) -> Data {
        let json: [String: Any] = [
            "type": "FeatureCollection",
            "features": [[
                "type": "Feature",
                "properties": ["distance": distanceM, "distance_units": "meters", "mode": "drive"],
                "geometry": [
                    "type": "MultiLineString",
                    "coordinates": parts.map { part in part.map { [$0.lon, $0.lat] } }
                ]
            ]]
        ]
        // swiftlint:disable:next force_try
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func errorBody(_ message: String) -> Data {
        // swiftlint:disable:next force_try
        try! JSONSerialization.data(withJSONObject: ["statusCode": 400, "error": "Bad Request", "message": message])
    }

    private func http(_ status: Int, _ url: URL?) -> URLResponse {
        HTTPURLResponse(url: url ?? URL(fileURLWithPath: "/"), statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    /// Three photo positions ~1.1 km apart along a meridian.
    private func waypoints(count: Int) -> [RouteMatchPoint] {
        (0..<count).map {
            RouteMatchPoint(ts: 1_752_600_000 + Double($0 * 3_600), lat: -32.0 + Double($0) * 0.01, lon: 115.75)
        }
    }

    func testReconstructedRouteCarriesEveryPhotoAsAViaWaypoint() async throws {
        let road = [GeoPoint(lat: -32.0, lon: 115.75), GeoPoint(lat: -31.98, lon: 115.751)]
        let seenURL = Locked<URL?>(nil)
        let provider = GeoapifyRouteProvider(config: routingConfig) { request in
            seenURL.set(request.url)
            return (self.routeBody(distanceM: 2_500, parts: [road]), self.http(200, request.url))
        }

        let outcome = try await provider.route(waypoints(count: 3))
        XCTAssertEqual(outcome?.geometry, road)

        let url = try XCTUnwrap(seenURL.get()?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://routing.invalid/v1/routing?"), "sparse legs go to /v1/routing")
        let waypointsParam = try XCTUnwrap(
            URLComponents(string: url)?.queryItems?.first { $0.name == "waypoints" }?.value
        )
        XCTAssertEqual(
            waypointsParam.components(separatedBy: "|").count, 3,
            "the intermediate photo rides along as a via-waypoint (PD-3)"
        )
        XCTAssertEqual(
            waypointsParam.components(separatedBy: "|").first, "-32.000000,115.750000",
            "Geoapify takes latitude first — the opposite of the OSRM path this replaced"
        )
        XCTAssertTrue(url.contains("mode=drive"))
        XCTAssertFalse(url.contains("timestamps="), "routing takes no timestamps")
    }

    /// The key reaches the request. This is the half of the 2026-08-20
    /// `withBaseURL` bug that a caller would actually feel: every desk harness
    /// builds its provider that way, and a dropped key is a 401 reported as
    /// "the provider is unreachable".
    func testTheAPIKeyIsCarriedIntoTheRequest() async throws {
        let seenURL = Locked<URL?>(nil)
        let provider = GeoapifyRouteProvider(config: routingConfig) { request in
            seenURL.set(request.url)
            return (self.routeBody(distanceM: 2_500, parts: [[GeoPoint(lat: -32, lon: 115.75),
                                                              GeoPoint(lat: -31.98, lon: 115.751)]]),
                    self.http(200, request.url))
        }
        _ = try await provider.route(waypoints(count: 3))

        let items = try XCTUnwrap(URLComponents(string: try XCTUnwrap(seenURL.get()?.absoluteString))?.queryItems)
        XCTAssertEqual(items.first { $0.name == "apiKey" }?.value, "test-key")
    }

    /// A keyless build is the Cloudflare Worker's shape (`Docs/pre-launch.md`):
    /// the key lives in the Worker, so the app must send no `apiKey` at all
    /// rather than an empty one, which reads as an invalid key.
    func testAKeylessBuildSendsNoAPIKeyParameter() async throws {
        let seenURL = Locked<URL?>(nil)
        let provider = GeoapifyRouteProvider(config: matchingConfig.withBaseURL("https://worker.invalid")) { request in
            seenURL.set(request.url)
            return (self.routeBody(distanceM: 2_500, parts: [[GeoPoint(lat: -32, lon: 115.75),
                                                              GeoPoint(lat: -31.98, lon: 115.751)]]),
                    self.http(200, request.url))
        }
        _ = try await provider.route(waypoints(count: 3))

        let url = try XCTUnwrap(seenURL.get()?.absoluteString)
        XCTAssertFalse(url.contains("apiKey"), "got: \(url)")
    }

    /// Measured wire fact: a multi-waypoint route arrives as one part per
    /// waypoint pair, with the joint coordinate repeated across the seam.
    /// Storing the repeat would put zero-length steps into `matched_polyline`.
    func testMultiPartGeometryIsStitchedWithoutRepeatingTheJoint() async throws {
        let joint = GeoPoint(lat: -31.99, lon: 115.7505)
        let first = [GeoPoint(lat: -32.0, lon: 115.75), joint]
        let second = [joint, GeoPoint(lat: -31.98, lon: 115.751)]
        let provider = GeoapifyRouteProvider(config: routingConfig) { request in
            (self.routeBody(distanceM: 2_500, parts: [first, second]), self.http(200, request.url))
        }

        let outcome = try await provider.route(waypoints(count: 3))
        XCTAssertEqual(outcome?.geometry, [first[0], joint, second[1]], "the shared joint appears once")
    }

    /// PD-3 outlier protection: routing always answers *something* drivable, so
    /// an implausible detour must be rejected rather than drawn as real road.
    func testImplausibleDetourIsRejectedSoTheLegStaysRaw() async throws {
        let road = [GeoPoint(lat: -32.0, lon: 115.75), GeoPoint(lat: -31.98, lon: 115.751)]
        let provider = GeoapifyRouteProvider(config: routingConfig) { request in
            // ~2.2 km of straight line answered with a 300 km "route".
            (self.routeBody(distanceM: 300_000, parts: [road]), self.http(200, request.url))
        }
        let outcome = try await provider.route(waypoints(count: 3))
        XCTAssertNil(outcome)
    }

    func testPlausibleDetourWithinRatioIsAccepted() async throws {
        let road = [GeoPoint(lat: -32.0, lon: 115.75), GeoPoint(lat: -31.98, lon: 115.751)]
        let straightM = RouteWaypoints.straightLineM(waypoints(count: 3))
        let provider = GeoapifyRouteProvider(config: routingConfig) { request in
            // Just inside route_max_detour_ratio — roads are never straight.
            (self.routeBody(distanceM: straightM * 2.4, parts: [road]), self.http(200, request.url))
        }
        let outcome = try await provider.route(waypoints(count: 3))
        XCTAssertNotNil(outcome)
    }

    /// The class the OSRM snap radius used to guard — a waypoint with no road
    /// anywhere near it — refused by the provider itself, and mapped to the same
    /// keep-raw verdict (ADR 2026-08-20 (d)).
    func testNoSuitableEdgesIsCleanFallbackNotError() async throws {
        let provider = GeoapifyRouteProvider(config: routingConfig) { request in
            (self.errorBody("No suitable edges near location. Please check waypoint coordinate order (lat/lon)."),
             self.http(400, request.url))
        }
        let outcome = try await provider.route(waypoints(count: 3))
        XCTAssertNil(outcome, "an unroutable leg keeps raw geometry (PD-2)")
    }

    /// A bad key is not a verdict about the geography — it must throw, so the
    /// film says "we could not reach routing" rather than "there is no road".
    func testAnUnauthorizedResponseIsRefusedRatherThanKeptRaw() async throws {
        let provider = GeoapifyRouteProvider(config: routingConfig) { request in
            // swiftlint:disable:next force_try
            let body = try! JSONSerialization.data(
                withJSONObject: ["statusCode": 401, "error": "Unauthorized", "message": "Invalid apiKey"]
            )
            return (body, self.http(401, request.url))
        }
        do {
            _ = try await provider.route(waypoints(count: 3))
            XCTFail("a 401 must not be reported as an unroutable leg")
        } catch let failure as RouteProviderFailure {
            XCTAssertEqual(failure, .refused(status: 401))
        }
    }

    /// `RouteProviderFailure.rateLimited` is unreachable on Geoapify, which sheds
    /// load as a TCP reset — but the pre-launch Cloudflare Worker can answer 429,
    /// so the case is kept **and exercised** rather than trusted to be dead
    /// (Arch.md §7.2, `HANDOFF.md` item 2).
    func testA429IsRateLimitedWithTheServersOwnRetryAdvice() async throws {
        let provider = GeoapifyRouteProvider(config: routingConfig) { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil,
                headerFields: ["Retry-After": "30"]
            )!
            return (Data(), response)
        }
        do {
            _ = try await provider.route(waypoints(count: 3))
            XCTFail("a 429 must not be reported as an unroutable leg")
        } catch let failure as RouteProviderFailure {
            XCTAssertEqual(failure, .rateLimited(retryAfterS: 30))
        }
    }

    func testEmptyBaseURLDisablesReconstructionWithoutNetwork() async throws {
        let provider = GeoapifyRouteProvider(config: routingConfig.withBaseURL("")) { _ in
            XCTFail("disabled reconstruction must never touch the transport")
            throw URLError(.badURL)
        }
        let outcome = try await provider.route(waypoints(count: 3))
        XCTAssertNil(outcome)
    }

    // MARK: - Waypoint hygiene

    func testClusteredWaypointsAreThinnedButEndpointsSurvive() {
        // Five points, the middle three within ~11 m of each other (EXIF noise
        // at one place) — they must not pin the route to a parking bay.
        let noisy = [
            RouteMatchPoint(ts: 0, lat: -32.00, lon: 115.75),
            RouteMatchPoint(ts: 1, lat: -31.98, lon: 115.75),
            RouteMatchPoint(ts: 2, lat: -31.9801, lon: 115.75),
            RouteMatchPoint(ts: 3, lat: -31.9802, lon: 115.75),
            RouteMatchPoint(ts: 4, lat: -31.96, lon: 115.75)
        ]
        let thinned = RouteWaypoints.thinned(noisy, minSpacingM: 250, limit: 100)
        XCTAssertEqual(thinned.count, 3, "the noise collapses to one via")
        XCTAssertEqual(thinned.first?.lat, -32.00, "the leg's start anchor is never dropped")
        XCTAssertEqual(thinned.last?.lat, -31.96, "nor its end anchor")
    }

    func testWaypointsAreCappedAtTheRequestLimitKeepingBothEnds() {
        let many = (0..<400).map {
            RouteMatchPoint(ts: Double($0), lat: -32.0 + Double($0) * 0.01, lon: 115.75)
        }
        let thinned = RouteWaypoints.thinned(many, minSpacingM: 250, limit: 100)
        XCTAssertEqual(thinned.count, 100, "the provider's per-request location cap")
        XCTAssertEqual(thinned.first?.lat, many.first?.lat)
        XCTAssertEqual(thinned.last?.lat, many.last?.lat)
    }

    /// A leg whose waypoints all collapsed onto one position has no straight
    /// line to measure against, so there is no ratio and nothing honest to draw.
    /// Guarded in the policy rather than in a provider, where it used to live.
    func testACollapsedLegIsRejectedRatherThanDividedByZero() {
        let sameSpot = (0..<3).map { RouteMatchPoint(ts: Double($0), lat: -32.0, lon: 115.75) }
        XCTAssertFalse(
            RoutePlausibility.acceptsRoute(distanceM: 1_200, through: sameSpot, maxDetourRatio: 2.5)
        )
    }

    func testTwoWaypointLegIsSentUnthinned() {
        let pair = waypoints(count: 2)
        XCTAssertEqual(RouteWaypoints.thinned(pair, minSpacingM: 100_000, limit: 100).count, 2,
                       "a leg is its two stop anchors at minimum — never thinned below that")
    }
}
