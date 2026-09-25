import KamomeConfig
@testable import KamomeRouteMatching
import XCTest

/// **"No drive path" is asked again on foot** (ADR 2026-09-25 (b)).
///
/// The Iceland film flew a plane from Skógar to the Seljavallalaug pool. The
/// drive profile answered `No path could be found`, and that message was read
/// as the sea. The pool photo sits on a footpath, and its snapped road joins
/// nothing. The walk profile tells land from sea: a walk route with no ferry
/// is land, and anything else keeps the crossing it always was. Every wire
/// shape below was measured through the Worker on 2026-09-25.
final class RouteLandConnectionTests: XCTestCase {
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
        routeWaypointRadiusM: 500
    )

    /// Skógafoss → Seljavallalaug pool, public landmark coordinates.
    private let leg = [
        RouteMatchPoint(ts: 0, lat: 63.5321, lon: -19.5114),
        RouteMatchPoint(ts: 3_600, lat: 63.5654, lon: -19.6087)
    ]

    private func walkBody(ferry: Bool?) -> Data {
        var properties: [String: Any] = ["mode": "walk", "distance": 12_418, "distance_units": "meters"]
        if let ferry { properties["ferry"] = ferry }
        let json: [String: Any] = [
            "type": "FeatureCollection",
            "features": [[
                "type": "Feature",
                "properties": properties,
                "geometry": ["type": "LineString", "coordinates": [[-19.5114, 63.5321], [-19.6087, 63.5654]]]
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

    private func mode(of request: URLRequest) -> String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == "mode" }?.value
    }

    /// A provider whose drive profile says `No path`, and whose walk profile
    /// answers `walk`. Records every request it sees.
    private func provider(
        seen: Locked<[URLRequest]>,
        walk: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)
    ) -> GeoapifyRouteProvider {
        GeoapifyRouteProvider(config: config) { request in
            seen.set(seen.get() + [request])
            if self.mode(of: request) == "walk" { return try walk(request) }
            return (self.errorBody("No path could be found for input"), self.http(400, request.url))
        }
    }

    /// The Iceland case: no drive path, but a walk with no ferry. Land, so not
    /// a crossing, and the walk request carries the same waypoints.
    func testNoDrivePathThatCanBeWalkedIsLandNotACrossing() async throws {
        let seen = Locked<[URLRequest]>([])
        let provider = provider(seen: seen) { (self.walkBody(ferry: nil), self.http(200, $0.url)) }

        let outcome = try await provider.route(leg)

        XCTAssertEqual(outcome, .offTheRoadNetwork, "walk-only land is dashed with the trip's vehicle, never flown")
        XCTAssertEqual(seen.get().map { mode(of: $0) }, ["drive", "walk"])
        func waypoints(_ request: URLRequest) -> String? {
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
                .queryItems?.first { $0.name == "waypoints" }?.value
        }
        XCTAssertEqual(waypoints(seen.get()[1]), waypoints(seen.get()[0]), "the same leg, asked on foot")
    }

    /// Ishigaki → Taketomi: walking needs the ferry, so it is the sea.
    func testNoDrivePathWhoseWalkNeedsAFerryIsStillACrossing() async throws {
        let seen = Locked<[URLRequest]>([])
        let provider = provider(seen: seen) { (self.walkBody(ferry: true), self.http(200, $0.url)) }
        let outcome = try await provider.route(leg)
        XCTAssertEqual(outcome, .noRoadHere)
    }

    /// Taoyuan → Miyako: over the walk profile's 100 km cap. Any walk 400 keeps
    /// the crossing, which is what the leg was before the walk question.
    func testNoDrivePathTheWalkProfileRefusesIsStillACrossing() async throws {
        for message in ["Too long distance between locations. Distance should not exceed 100000 meters",
                        "No path could be found for input",
                        "No suitable edges near location."] {
            let seen = Locked<[URLRequest]>([])
            let provider = provider(seen: seen) { (self.errorBody(message), self.http(400, $0.url)) }
            let outcome = try await provider.route(leg)
            XCTAssertEqual(outcome, .noRoadHere, "walk said: \(message)")
        }
    }

    /// A walk 200 this client cannot read proves no land path.
    func testAnUnreadableWalkAnswerIsStillACrossing() async throws {
        let seen = Locked<[URLRequest]>([])
        let provider = provider(seen: seen) { request in
            // swiftlint:disable:next force_try
            let body = try! JSONSerialization.data(withJSONObject: ["type": "FeatureCollection", "features": []])
            return (body, self.http(200, request.url))
        }
        let outcome = try await provider.route(leg)
        XCTAssertEqual(outcome, .noRoadHere)
    }

    /// Nobody answered the walk question, so the leg is not settled. It throws
    /// rather than store a crossing that would never be asked again.
    func testAnUnansweredWalkQuestionThrowsRatherThanStoreACrossing() async throws {
        let seen = Locked<[URLRequest]>([])
        let provider = provider(seen: seen) { _ in throw URLError(.timedOut) }
        do {
            _ = try await provider.route(leg)
            XCTFail("an unanswered walk question must not settle the leg")
        } catch let failure as RouteProviderFailure {
            guard case .unreachable = failure else { return XCTFail("got \(failure)") }
        }
    }

    /// The walk question is asked only after `No path`. A routed leg and a
    /// `No suitable edges` leg are already settled by the drive answer.
    func testTheWalkQuestionIsAskedOnlyAfterNoPath() async throws {
        let seen = Locked<[URLRequest]>([])
        let beach = GeoapifyRouteProvider(config: config) { request in
            seen.set(seen.get() + [request])
            return (self.errorBody("No suitable edges near location."), self.http(400, request.url))
        }
        let outcome = try await beach.route(leg)
        XCTAssertEqual(outcome, .offTheRoadNetwork)
        XCTAssertEqual(seen.get().map { mode(of: $0) }, ["drive"])
    }
}
