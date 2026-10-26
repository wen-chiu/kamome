import KamomeConfig
@testable import KamomeRouteMatching
import XCTest

/// **A route of one point goes nowhere, so it is not the leg's road** (#256).
///
/// Until #256 a route that came back as a single point was read as an answer
/// the client could not read — `.notEstablished`, which stores nothing, so the
/// leg was asked again on every export. It is a route the provider did draw,
/// and one that cannot be the way between two places the photographs show
/// apart: the policy refuses it like a route the detour gate refuses.
final class RouteOnePointAnswerTests: XCTestCase {
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

    // Synthetic places (§0) — round numbers, never a real trip. About 150 m apart.
    private let leg = [
        RouteMatchPoint(ts: 0, lat: 40.0, lon: -100.0),
        RouteMatchPoint(ts: 1_200, lat: 40.00135, lon: -100.0)
    ]
    private let snapped = [-100.0, 40.0]

    private func answer(_ geometry: [String: Any]) -> GeoapifyRouteProvider {
        let json: [String: Any] = [
            "type": "FeatureCollection",
            "features": [[
                "type": "Feature",
                "properties": ["distance": 0, "distance_units": "meters", "mode": "drive"],
                "geometry": geometry
            ]]
        ]
        // swiftlint:disable:next force_try
        let body = try! JSONSerialization.data(withJSONObject: json)
        return GeoapifyRouteProvider(config: config) { request in
            (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    /// Both shapes that read as one point: a part whose ends are one place,
    /// and a line of a single coordinate.
    func testARouteOfOnePointIsRefusedNotUnread() async throws {
        let shapes: [String: [String: Any]] = [
            "one part, both ends the same place": ["type": "MultiLineString", "coordinates": [[snapped, snapped]]],
            "a line of one coordinate": ["type": "LineString", "coordinates": [snapped]]
        ]
        for (name, geometry) in shapes {
            let outcome = try await answer(geometry).route(leg)
            XCTAssertEqual(outcome, .implausible, "\(name): a route that goes nowhere is not the leg's road")
        }
    }

    /// A geometry with no point in it is still nothing the client could read:
    /// nothing was learnt, so nothing is settled and the leg is asked again.
    func testAGeometryWithNoPointIsStillUnread() async throws {
        let outcome = try await answer(["type": "Point", "coordinates": snapped]).route(leg)
        XCTAssertEqual(outcome, .notEstablished(.unreadableAnswer))
    }
}
