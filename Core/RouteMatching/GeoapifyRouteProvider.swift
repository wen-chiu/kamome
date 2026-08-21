import Foundation
import KamomeConfig

/// Geoapify `/v1/routing` client — the reconstruction backend since 2026-08-20
/// (`Docs/decisions.md` 2026-08-20), replacing the self-hosted OSRM that only
/// routed the four regions `Deploy/regions.json` preloaded and resolved nowhere
/// but the developer's own Wi-Fi.
///
/// Every Geoapify-specific fact lives in this one file — URL shape, GeoJSON
/// response schema, error vocabulary — the same one-file-per-backend discipline
/// as `MapKitSnapshotProvider.swift`. Kamome's own policies do not: waypoint
/// thinning and the PD-3 detour gate are in `RoutePlausibility.swift`, because
/// they are the same policy whoever answers the request.
///
/// **The wire facts, measured against a live key on 2026-08-20** (public
/// landmark coordinates only, §0 respected):
///
/// - `/v1/routing` is **GET-only**; `POST` returns 404.
/// - Waypoints are `lat,lon` pairs separated by `|` — **latitude first**, which
///   is the opposite of the OSRM path this replaces. A percent-encoded `%7C` is
///   accepted, so `URLComponents` may build the query.
/// - The answer is GeoJSON: `properties.distance` in metres, and a
///   `MultiLineString` with **one part per waypoint pair**, adjacent parts
///   sharing a duplicated joint coordinate.
/// - There is **no snap-radius parameter**, and unknown query parameters are
///   silently ignored rather than refused (ADR 2026-08-20 (d)). A waypoint with
///   no road near it is refused natively with `400 No suitable edges near
///   location`, which is the keep-raw verdict this provider maps it to.
/// - A bad key is `401 Invalid apiKey`. No 429 has ever been observed — see
///   `RouteProviderFailure.rateLimited` for why the case is kept anyway.
///
/// With `matching.base_url` empty this provider is a no-network no-op returning
/// nil, so simulator runs and CI never need an endpoint or a key.
public struct GeoapifyRouteProvider: RouteReconstructing {
    /// Injectable so tests replay recorded responses without a live endpoint.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Kamome reconstructs drive and scooter legs only (PD-8, enforced by
    /// `RouteMatchService.shouldReconstruct`), so the profile is fixed here
    /// rather than plumbed through the boundary. Walk legs get their own
    /// profile when spec v1.8 §4.4.1 is built — `mode=walk` answers today — and
    /// that is the point at which this becomes a parameter.
    private static let driveProfile = "drive"

    private let config: TrackingConfig.Matching
    private let transport: Transport

    public init(config: TrackingConfig.Matching, transport: Transport? = nil) {
        self.config = config
        self.transport = transport ?? { request in
            try await URLSession.shared.data(for: request)
        }
    }

    /// Every `return nil` here is a leg that will draw dashed, and each is named
    /// in the log as it happens — "disabled", "no suitable edges", "detour 4.1×"
    /// and a transport failure are four very different problems with one
    /// identical symptom in the finished film.
    public func route(_ waypoints: [RouteMatchPoint]) async throws -> RouteMatchOutcome? {
        guard !config.baseURL.isEmpty else {
            KamomeLog.routing.notice("route: skipped — matching.base_url is empty, so the leg stays raw (PD-2)")
            return nil
        }
        let thinned = RouteWaypoints.thinned(
            waypoints, minSpacingM: config.routeWaypointMinSpacingM, limit: config.chunkSize
        )
        guard thinned.count >= 2, let url = requestURL(for: thinned) else {
            KamomeLog.routing.notice("route: skipped — \(thinned.count) usable waypoints after thinning")
            return nil
        }

        guard let data = try await fetch(url) else { return nil }
        let body = try JSONDecoder().decode(Response.self, from: data)
        guard let route = body.features?.first else {
            KamomeLog.routing.notice("route: the provider returned no route feature — leg stays raw")
            return nil
        }
        let geometry = route.geometry.points
        guard geometry.count >= 2 else {
            KamomeLog.routing.notice("route: the provider returned \(geometry.count) points — leg stays raw")
            return nil
        }
        guard RoutePlausibility.acceptsRoute(
            distanceM: route.properties.distance,
            through: thinned,
            maxDetourRatio: config.routeMaxDetourRatio
        ) else { return nil }

        KamomeLog.routing.notice("""
            route: reconstructed \(route.properties.distance / 1000, format: .fixed(precision: 1)) km \
            from \(thinned.count) waypoints
            """)
        // Routing reports no confidence of its own. Passing the gate is the
        // verdict: the caller stores the geometry, which is what marks the leg
        // reconstructed rather than inferred.
        return RouteMatchOutcome(geometry: geometry, confidence: 1)
    }

    /// One request, with the provider's verdicts told apart from its failures.
    ///
    /// Returns nil for "these waypoints cannot be joined by road", answered as
    /// HTTP 400 — a clean keep-raw verdict, and what a leg across water or a
    /// photograph taken on a beach correctly gets. **Throws** for anything else,
    /// because a transport failure is not a verdict about the geography.
    ///
    /// **§0: the URL is never logged.** GET-only means it carries the API key
    /// *and* real trip coordinates in its query string, and a device log is the
    /// last place either belongs. Only the host is named, and the provider's own
    /// message is redacted before it is written (`HANDOFF.md` item 0b).
    private func fetch(_ url: URL) async throws -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = config.timeoutS

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            KamomeLog.routing.error("""
                route: TRANSPORT FAILED against \(config.baseURL, privacy: .public) — \
                \(error.localizedDescription, privacy: .public)
                """)
            throw RouteProviderFailure.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { return data }

        switch http.statusCode {
        case 200:
            return data
        case 400:
            // The provider's own geography verdict — "No suitable edges near
            // location" (no road anywhere near a waypoint) or "No path could be
            // found". This is the class the OSRM snap radius used to guard, and
            // it is refused natively here (ADR 2026-08-20 (d)).
            KamomeLog.routing.notice(
                "route: the provider said \(Self.redacted(Self.message(in: data)), privacy: .public) — leg stays raw"
            )
            return nil
        case 429:
            // Never observed on Geoapify, which sheds load as a TCP reset. Kept
            // because the pre-launch Cloudflare Worker is the natural place to
            // throttle and *can* answer 429 with `Retry-After`.
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            KamomeLog.routing.error(
                "route: RATE LIMITED by \(config.baseURL, privacy: .public), retry after \(retryAfter ?? -1)s"
            )
            throw RouteProviderFailure.rateLimited(retryAfterS: retryAfter)
        default:
            KamomeLog.routing.error("""
                route: HTTP \(http.statusCode) from \(config.baseURL, privacy: .public) — \
                \(Self.redacted(Self.message(in: data)), privacy: .public)
                """)
            throw RouteProviderFailure.refused(status: http.statusCode)
        }
    }

    // MARK: - Geoapify wire format

    private struct Response: Decodable {
        struct Feature: Decodable {
            let properties: RouteProperties
            let geometry: Geometry
        }

        let features: [Feature]?
    }

    private struct RouteProperties: Decodable {
        /// Road distance in metres — the detour gate's input.
        let distance: Double
    }

    /// GeoJSON geometry, flattened to the trace order Kamome stores.
    ///
    /// A multi-waypoint route comes back as one part per waypoint pair, and
    /// adjacent parts repeat the joint coordinate. Dropping the repeat keeps the
    /// stored polyline free of zero-length steps, which would otherwise survive
    /// simplification and be encoded into `matched_polyline`.
    private struct Geometry: Decodable {
        let points: [GeoPoint]

        private enum CodingKeys: String, CodingKey {
            case type, coordinates
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let parts: [[[Double]]]
            switch try container.decode(String.self, forKey: .type) {
            case "LineString":
                parts = [try container.decode([[Double]].self, forKey: .coordinates)]
            case "MultiLineString":
                parts = try container.decode([[[Double]]].self, forKey: .coordinates)
            case let other:
                // Not a failure the caller can act on differently from an empty
                // route: the leg keeps its raw geometry either way.
                KamomeLog.routing.notice("route: unexpected geometry type \(other, privacy: .public) — leg stays raw")
                parts = []
            }
            var flattened: [GeoPoint] = []
            for part in parts {
                for pair in part where pair.count >= 2 {
                    // GeoJSON is [longitude, latitude].
                    let point = GeoPoint(lat: pair[1], lon: pair[0])
                    if point != flattened.last { flattened.append(point) }
                }
            }
            points = flattened
        }
    }

    private struct ErrorBody: Decodable {
        let message: String?
    }

    private static func message(in data: Data) -> String {
        (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message ?? "no message"
    }

    /// §0 belt and braces: a provider's error text is not ours, and nothing
    /// stops a future one from quoting the coordinates back. Anything shaped
    /// like a coordinate is replaced before the string reaches `KamomeLog`.
    private static func redacted(_ message: String) -> String {
        // Extended literal: a bare `/-?…/` reads as an operator to the parser.
        message.replacing(#/-?\d+\.\d{3,}/#, with: "…")
    }

    private func requestURL(for waypoints: [RouteMatchPoint]) -> URL? {
        guard var components = URLComponents(string: "\(config.baseURL)/v1/routing") else { return nil }
        // Latitude first — the opposite of the OSRM path this replaces.
        let coordinates = waypoints
            .map { String(format: "%.6f,%.6f", $0.lat, $0.lon) }
            .joined(separator: "|")
        var items = [
            URLQueryItem(name: "waypoints", value: coordinates),
            URLQueryItem(name: "mode", value: Self.driveProfile)
        ]
        // Empty is a legitimate state, and the one the pre-launch Cloudflare
        // Worker ships in: the key lives in the Worker and the app sends none.
        if !config.apiKey.isEmpty {
            items.append(URLQueryItem(name: "apiKey", value: config.apiKey))
        }
        components.queryItems = items
        return components.url
    }
}
