import KamomeConfig
@testable import KamomeRouteMatching
import XCTest

/// **A waypoint the drive profile refuses is asked again from where a walk
/// reaches it** (ADR 2026-10-01).
///
/// A photograph on the sand about 500 m or more from the car park got `400 No
/// suitable edges`, and the whole leg lost its road. The walk profile still
/// reaches the beach, and the points where its route joins the network are
/// points the drive profile accepts. Every wire shape below was measured through
/// the Worker on 2026-10-01 with public landmark coordinates (Vík → Reynisfjara).
final class RouteWalkSnapTests: XCTestCase {
    private let config = TrackingConfig.Matching(
        baseURL: "https://routing.invalid",
        chunkSize: 100,
        confidenceMin: 0.5,
        radiusM: 25,
        timeoutS: 10,
        tripBudgetS: 60,
        displayEpsilonM: 5,
        routeMaxDetourRatio: 2.5,
        routeWaypointMinSpacingM: 250,
        routeWaypointRadiusM: 500,
        routeOffNetworkWalkSnapMaxM: 650
    )

    /// A town, a photograph beside the road on the way, and one on the sand.
    private let town = GeoPoint(lat: 63.4186, lon: -19.0083)
    private let layby = GeoPoint(lat: 63.4290, lon: -19.0300)
    private let sand = GeoPoint(lat: 63.4044, lon: -19.0588)
    /// Where the walk route reaches the sand: about 555 m north of it.
    private let pathEnd = GeoPoint(lat: 63.4094, lon: -19.0588)

    private var leg: [RouteMatchPoint] {
        [town, layby, sand].enumerated().map {
            RouteMatchPoint(ts: Double($0.offset) * 3_600, lat: $0.element.lat, lon: $0.element.lon)
        }
    }

    /// One `MultiLineString` part per waypoint pair, adjacent parts sharing the joint.
    private func routeBody(mode: String, distanceM: Double, parts: [[GeoPoint]]) -> Data {
        let json: [String: Any] = [
            "type": "FeatureCollection",
            "features": [[
                "type": "Feature",
                "properties": ["mode": mode, "distance": distanceM, "distance_units": "meters"],
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

    private func query(_ name: String, of request: URLRequest) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == name }?.value
    }

    private func walkBody(reaching end: GeoPoint) -> Data {
        let bend = GeoPoint(lat: 63.4250, lon: -19.0200)
        return routeBody(mode: "walk", distanceM: 4_446, parts: [[town, bend, layby], [layby, end]])
    }

    private let noSuitableEdges = "No suitable edges near location. Please check waypoint coordinate order (lat/lon)."

    /// A provider whose first drive answer is `No suitable edges`. `walk`
    /// answers the walk request and `secondDrive` the drive request after it.
    private func provider(
        seen: Locked<[URLRequest]>,
        walk: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse),
        secondDrive: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse) = { _ in throw URLError(.badURL) }
    ) -> GeoapifyRouteProvider {
        GeoapifyRouteProvider(config: config) { request in
            let earlier = seen.get()
            seen.set(earlier + [request])
            if self.query("mode", of: request) == "walk" { return try walk(request) }
            if earlier.isEmpty { return (self.errorBody(self.noSuitableEdges), self.http(400, request.url)) }
            return try secondDrive(request)
        }
    }

    /// The beach case: drive refuses the sand, a walk reaches it 555 m away,
    /// and drive routes to that point. The leg has its road.
    func testARefusedBeachIsRoutedFromWhereTheWalkReachesIt() async throws {
        let seen = Locked<[URLRequest]>([])
        let road = [town, GeoPoint(lat: 63.4300, lon: -19.0250), layby, pathEnd]
        let provider = provider(
            seen: seen,
            walk: { (self.walkBody(reaching: self.pathEnd), self.http(200, $0.url)) },
            secondDrive: { (self.routeBody(mode: "drive", distanceM: 5_000, parts: [road]), self.http(200, $0.url)) }
        )

        let outcome = try await provider.route(leg)

        XCTAssertEqual(outcome.outcome?.geometry, road, "the drive route to the path's end is the leg's road")
        XCTAssertEqual(seen.get().map { query("mode", of: $0) }, ["drive", "walk", "drive"])
        XCTAssertEqual(
            query("waypoints", of: seen.get()[1]), query("waypoints", of: seen.get()[0]),
            "the walk is asked about the same places"
        )
        XCTAssertEqual(
            query("waypoints", of: seen.get()[2]),
            "63.418600,-19.008300|63.429000,-19.030000|63.409400,-19.058800",
            "drive is asked again through where the walk joined the network, in order"
        )
    }

    /// A walk that reaches the sand only from farther than
    /// `route_off_network_walk_snap_max_m` leaves the leg dashed, and drive is
    /// not asked again: a road ending that far away is not the way there.
    func testAWalkThatReachesItFromTooFarLeavesTheLegOffTheNetwork() async throws {
        let seen = Locked<[URLRequest]>([])
        let far = GeoPoint(lat: 63.4104, lon: -19.0588) // about 667 m from the sand
        let provider = provider(seen: seen, walk: { (self.walkBody(reaching: far), self.http(200, $0.url)) })

        let outcome = try await provider.route(leg)

        XCTAssertEqual(outcome, .offTheRoadNetwork)
        XCTAssertEqual(seen.get().map { query("mode", of: $0) }, ["drive", "walk"])
    }

    /// The limit is the config's, not a constant in the provider.
    func testTheLimitIsReadFromConfig() async throws {
        let seen = Locked<[URLRequest]>([])
        let tight = TrackingConfig.Matching(
            baseURL: "https://routing.invalid", chunkSize: 100, confidenceMin: 0.5, radiusM: 25, timeoutS: 10,
            tripBudgetS: 60, displayEpsilonM: 5, routeMaxDetourRatio: 2.5, routeWaypointMinSpacingM: 250,
            routeWaypointRadiusM: 500, routeOffNetworkWalkSnapMaxM: 500
        )
        let provider = GeoapifyRouteProvider(config: tight) { request in
            seen.set(seen.get() + [request])
            if self.query("mode", of: request) == "walk" {
                return (self.walkBody(reaching: self.pathEnd), self.http(200, request.url))
            }
            return (self.errorBody(self.noSuitableEdges), self.http(400, request.url))
        }
        let outcome = try await provider.route(leg)
        XCTAssertEqual(outcome, .offTheRoadNetwork, "555 m is past a 500 m limit")
        XCTAssertEqual(seen.get().count, 2)
    }

    /// Whatever the walk profile cannot answer leaves the leg what it was
    /// before this question existed — and never a crossing.
    func testAWalkThatDoesNotAnswerARouteLeavesTheLegOffTheNetwork() async throws {
        let unreadable: [Data] = [
            // swiftlint:disable:next force_try
            try! JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": []]),
            // One part for three waypoints: the joints cannot be told apart.
            routeBody(mode: "walk", distanceM: 4_446, parts: [[town, layby, pathEnd]])
        ]
        for body in unreadable {
            let seen = Locked<[URLRequest]>([])
            let provider = provider(seen: seen, walk: { (body, self.http(200, $0.url)) })
            let outcome = try await provider.route(leg)
            XCTAssertEqual(outcome, .offTheRoadNetwork)
            XCTAssertEqual(seen.get().count, 2, "drive is not asked again without a place to ask about")
        }
        for message in [noSuitableEdges, "No path could be found for input",
                        "Too long distance between locations. Distance should not exceed 100000 meters"] {
            let seen = Locked<[URLRequest]>([])
            let provider = provider(seen: seen, walk: { (self.errorBody(message), self.http(400, $0.url)) })
            let outcome = try await provider.route(leg)
            XCTAssertEqual(outcome, .offTheRoadNetwork, "walk said: \(message)")
        }
    }

    /// A second drive 400, of either kind, leaves the leg off the network. In
    /// particular `No path` here does not make a beach a crossing.
    func testASecondDriveRefusalLeavesTheLegOffTheNetwork() async throws {
        for message in [noSuitableEdges, "No path could be found for input"] {
            let seen = Locked<[URLRequest]>([])
            let provider = provider(
                seen: seen,
                walk: { (self.walkBody(reaching: self.pathEnd), self.http(200, $0.url)) },
                secondDrive: { (self.errorBody(message), self.http(400, $0.url)) }
            )
            let outcome = try await provider.route(leg)
            XCTAssertEqual(outcome, .offTheRoadNetwork, "drive said: \(message)")
            XCTAssertEqual(seen.get().count, 3, "and the land question is not asked on top")
        }
    }

    /// The road to the path's end still goes through the detour gate, measured
    /// against the places the photographs were taken.
    func testTheSecondDriveAnswerStillFacesTheDetourGate() async throws {
        let seen = Locked<[URLRequest]>([])
        let provider = provider(
            seen: seen,
            walk: { (self.walkBody(reaching: self.pathEnd), self.http(200, $0.url)) },
            secondDrive: {
                (self.routeBody(mode: "drive", distanceM: 40_000, parts: [[self.town, self.pathEnd]]),
                 self.http(200, $0.url))
            }
        )
        let outcome = try await provider.route(leg)
        XCTAssertEqual(outcome, .implausible, "about 4 km of straight line does not earn a 40 km road")
    }

    /// Nobody answering either question settles nothing: it throws, so the leg
    /// stays unasked and the next export asks again.
    func testAnUnansweredQuestionThrowsRatherThanStoreAVerdict() async throws {
        let unansweredWalk = provider(seen: Locked([]), walk: { _ in throw URLError(.timedOut) })
        let unansweredDrive = provider(
            seen: Locked([]),
            walk: { (self.walkBody(reaching: self.pathEnd), self.http(200, $0.url)) },
            secondDrive: { _ in throw URLError(.timedOut) }
        )
        for provider in [unansweredWalk, unansweredDrive] {
            do {
                _ = try await provider.route(leg)
                XCTFail("an unanswered question must not settle the leg")
            } catch let failure as RouteProviderFailure {
                guard case .unreachable = failure else { return XCTFail("got \(failure)") }
            }
        }
    }
}
