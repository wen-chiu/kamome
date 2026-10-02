import Foundation
import KamomeConfig
import KamomeTrackingEngine

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
///   location` — from about 500 m out, on the one beach measured (ADR
///   2026-10-01) — and is asked again from where a walk reaches it
///   (`routeFromWhereAWalkReaches`) before it keeps its raw leg.
/// - A bad key is `401 Invalid apiKey`. No 429 has ever been observed — see
///   `RouteProviderFailure.rateLimited` for why the case is kept anyway.
///
/// With `matching.base_url` empty this provider is a no-network no-op answering
/// `.notEstablished(.routingDisabled)`, so simulator runs and CI never need an
/// endpoint or a key — and, importantly, a disabled endpoint never reads as
/// "there is no road here".
public struct GeoapifyRouteProvider: RouteReconstructing {
    /// Injectable so tests replay recorded responses without a live endpoint.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Kamome reconstructs drive and scooter legs only (PD-8, enforced by
    /// `RouteMatchService.shouldReconstruct`), so the profile is fixed here
    /// rather than plumbed through the boundary. Walk legs get their own
    /// profile when spec v1.8 §4.4.1 is built — `mode=walk` answers today — and
    /// that is the point at which this becomes a parameter.
    private static let driveProfile = "drive"
    /// The profile the land question is asked on (`landConnection(through:)`).
    /// Never used to draw a leg: its geometry is thrown away.
    private static let walkProfile = "walk"

    private let config: TrackingConfig.Matching
    private let transport: Transport

    public init(config: TrackingConfig.Matching, transport: Transport? = nil) {
        self.config = config
        self.transport = transport ?? { request in
            try await URLSession.shared.data(for: request)
        }
    }

    /// Every answer but `.routed` is a leg that will draw dashed, and each is
    /// named — in the log as it happens, and now in the **return type**, because
    /// "disabled", "no suitable edges" and "detour 4.1×" are three very different
    /// problems with one identical symptom in the finished film, and exactly one
    /// of them is a crossing (`RouteReconstruction`).
    public func route(_ waypoints: [RouteMatchPoint]) async throws -> RouteReconstruction {
        guard !config.baseURL.isEmpty else {
            KamomeLog.routing.notice("route: skipped — matching.base_url is empty, so the leg stays raw (PD-2)")
            return .notEstablished(.routingDisabled)
        }
        let thinned = RouteWaypoints.thinned(
            waypoints, minSpacingM: config.routeWaypointMinSpacingM, limit: config.chunkSize
        )
        guard thinned.count >= 2, let url = requestURL(for: thinned, profile: Self.driveProfile) else {
            KamomeLog.routing.notice("route: skipped — \(thinned.count) usable waypoints after thinning")
            return .notEstablished(.tooFewWaypoints)
        }

        switch try await fetch(url) {
        case let .body(data): return try reconstruction(from: data, through: thinned)
        case .noRoadHere: return try await landConnection(through: thinned)
        case .offTheRoadNetwork: return try await routeFromWhereAWalkReaches(thinned)
        }
    }

    /// What a drive 200 establishes: a route that passes the detour gate, or
    /// the named reason it is not one. `waypoints` are the places the leg
    /// really went through, which is what the gate measures against.
    private func reconstruction(
        from data: Data, through waypoints: [RouteMatchPoint]
    ) throws -> RouteReconstruction {
        let body = try JSONDecoder().decode(Response.self, from: data)
        guard let route = body.features?.first else {
            KamomeLog.routing.notice("route: the provider returned no route feature — leg stays raw")
            return .notEstablished(.unreadableAnswer)
        }
        let geometry = route.geometry.points
        guard geometry.count >= 2 else {
            KamomeLog.routing.notice("route: the provider returned \(geometry.count) points — leg stays raw")
            return .notEstablished(.unreadableAnswer)
        }
        guard RoutePlausibility.acceptsRoute(
            distanceM: route.properties.distance,
            through: waypoints,
            maxDetourRatio: config.routeMaxDetourRatio
        ) else { return .implausible }

        KamomeLog.routing.notice("""
            route: reconstructed \(route.properties.distance / 1000, format: .fixed(precision: 1)) km \
            from \(waypoints.count) waypoints
            """)
        // Routing reports no confidence of its own. Passing the gate is the
        // verdict: the caller stores the geometry, which is what marks the leg
        // reconstructed rather than inferred.
        return .routed(RouteMatchOutcome(geometry: geometry, confidence: 1))
    }

    /// **A waypoint the drive profile refuses is moved to where a walk reaches
    /// it, and drive is asked again** (ADR 2026-10-01).
    ///
    /// The drive profile refuses a waypoint from about 500 m off the road, so a
    /// photograph on the sand cost the whole leg its road, and the leg out of
    /// that stop with it. The walk profile reaches further (both measured
    /// through the Worker on 2026-10-01, in the ADR), and a walk route's parts
    /// meet at the points where each waypoint joined the network: one part per
    /// waypoint pair on this profile too. Those points replace the waypoints
    /// and the drive profile is asked once more.
    ///
    /// **Every way this can fail leaves the leg what it was**,
    /// `.offTheRoadNetwork`: a walk 400, a walk answer that cannot be read, a
    /// waypoint moved farther than `route_off_network_walk_snap_max_m`, or a
    /// second drive 400 of either kind. A second drive answer that *is* a route
    /// goes through the same detour gate as any other, measured against the
    /// places the photographs were taken, not the moved ones. Nobody answering
    /// **throws**, as in `landConnection(through:)`, so the leg is asked again.
    ///
    /// The same waypoints go to the same decided provider (CLAUDE.md §0); the
    /// walk geometry is read for its joints and thrown away.
    private func routeFromWhereAWalkReaches(_ waypoints: [RouteMatchPoint]) async throws -> RouteReconstruction {
        guard let walkURL = requestURL(for: waypoints, profile: Self.walkProfile),
              case let .body(walkData) = try await fetch(walkURL),
              let walk = (try? JSONDecoder().decode(Response.self, from: walkData))?.features?.first,
              walk.geometry.joints.count == waypoints.count
        else { return .offTheRoadNetwork }

        let reached = zip(waypoints, walk.geometry.joints).map { waypoint, joint in
            RouteMatchPoint(ts: waypoint.ts, lat: joint.lat, lon: joint.lon, hAccM: waypoint.hAccM)
        }
        let farthestM = zip(waypoints, reached).map {
            Geo.distanceM(latA: $0.lat, lonA: $0.lon, latB: $1.lat, lonB: $1.lon)
        }.max() ?? 0
        guard farthestM <= config.routeOffNetworkWalkSnapMaxM else {
            KamomeLog.routing.notice("""
                route: off the road network, and a walk reaches it only \(farthestM, format: .fixed(precision: 0)) m \
                away (limit \(config.routeOffNetworkWalkSnapMaxM, format: .fixed(precision: 0)) m) — leg stays raw
                """)
            return .offTheRoadNetwork
        }
        guard let driveURL = requestURL(for: reached, profile: Self.driveProfile),
              case let .body(data) = try await fetch(driveURL)
        else { return .offTheRoadNetwork }
        KamomeLog.routing.notice("""
            route: off the road network, asked again from where a walk reaches it \
            (moved at most \(farthestM, format: .fixed(precision: 0)) m)
            """)
        return try reconstruction(from: data, through: waypoints)
    }

    /// **Is "no drive path" the sea, or land a car cannot reach?** Asked once,
    /// on the walk profile, after the drive profile said `No path could be
    /// found` (ADR 2026-09-25 (c)).
    ///
    /// `No path` only means the snapped ends sit on road pieces that do not
    /// join. The sea does that. So does a photograph on a footpath that snaps
    /// to a stub of track connected to nothing. The Iceland film flew a plane
    /// from Skógar to the Seljavallalaug pool this way. The walk profile tells
    /// them apart, measured through the Worker on 2026-09-25 with public
    /// landmark coordinates:
    ///
    /// | request (`mode=walk`) | answer | verdict |
    /// |---|---|---|
    /// | Skógafoss → Seljavallalaug pool | 200, 12.4 km, no `ferry` | land, `.offTheRoadNetwork` |
    /// | Ishigaki port → Taketomi port | 200, `properties.ferry: true` | sea, `.noRoadHere` |
    /// | Taoyuan airport → Miyako airport | `400 Too long distance` (walk cap 100 km) | `.noRoadHere` |
    ///
    /// **Only a walk route with no ferry on it moves the verdict.** Any 400 and
    /// any unreadable 200 keep `.noRoadHere`, which is what the leg was before
    /// this question existed. A walk request that nobody answered **throws**: the
    /// drive answer alone can no longer settle the leg, and a leg stored as a
    /// crossing is never asked again, so leaving it unestablished is the
    /// failure that heals. The same waypoints go to the same decided provider
    /// (CLAUDE.md §0), and no geometry is kept.
    private func landConnection(through waypoints: [RouteMatchPoint]) async throws -> RouteReconstruction {
        guard let url = requestURL(for: waypoints, profile: Self.walkProfile) else { return .noRoadHere }
        guard case let .body(data) = try await fetch(url),
              let route = (try? JSONDecoder().decode(Response.self, from: data))?.features?.first
        else { return .noRoadHere }
        if route.properties.ferry == true {
            KamomeLog.routing.notice("route: no drive path, and walking needs a ferry — a crossing")
            return .noRoadHere
        }
        KamomeLog.routing.notice("route: no drive path, but it can be walked — land, not a crossing")
        return .offTheRoadNetwork
    }

    /// What one HTTP exchange produced. A two-case enum rather than `Data?` for
    /// the reason the whole verdict lift exists: the nil that meant "there is no
    /// road here" was indistinguishable at the call site from any other, and this
    /// one is load-bearing.
    private enum Fetched {
        case body(Data)
        case noRoadHere
        case offTheRoadNetwork
    }

    /// One request, with the provider's verdicts told apart from its failures.
    ///
    /// Answers `.noRoadHere` for "these waypoints cannot be joined by road",
    /// answered as HTTP 400 — a clean keep-raw verdict, and what a leg across
    /// water or a photograph taken on a beach correctly gets. **Throws** for
    /// anything else, because a transport failure is not a verdict about the
    /// geography.
    ///
    /// **§0: the URL is never logged.** GET-only means it carries the API key
    /// *and* real trip coordinates in its query string, and a device log is the
    /// last place either belongs. Only the host is named, and the provider's own
    /// message is redacted before it is written (`HANDOFF.md` item 0b).
    private func fetch(_ url: URL) async throws -> Fetched {
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
        guard let http = response as? HTTPURLResponse else { return .body(data) }

        switch http.statusCode {
        case 200:
            return .body(data)
        case 400:
            // The provider's own geography verdict — "No suitable edges near
            // location" (no road anywhere near a waypoint) or "No path could be
            // found". This is the class the OSRM snap radius used to guard, and
            // it is refused natively here (ADR 2026-08-20 (d)).
            let message = Self.message(in: data)
            KamomeLog.routing.notice(
                "route: the provider said \(Self.redacted(message), privacy: .public) — leg stays raw"
            )
            return Self.verdict(for400: message) == .offTheRoadNetwork ? .offTheRoadNetwork : .noRoadHere
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
        /// `true` when the route rides a ferry. Absent otherwise (measured
        /// 2026-09-25): the sea/land answer in `landConnection(through:)`.
        let ferry: Bool?
    }

    /// GeoJSON geometry, flattened to the trace order Kamome stores.
    ///
    /// A multi-waypoint route comes back as one part per waypoint pair, and
    /// adjacent parts repeat the joint coordinate. Dropping the repeat keeps the
    /// stored polyline free of zero-length steps, which would otherwise survive
    /// simplification and be encoded into `matched_polyline`.
    private struct Geometry: Decodable {
        let points: [GeoPoint]
        /// Where each waypoint joined the network: the start of the first part,
        /// then the end of every part. One per waypoint when the answer has one
        /// part per waypoint pair; `routeFromWhereAWalkReaches` checks the count.
        let joints: [GeoPoint]

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
            var joints: [GeoPoint] = []
            for part in parts {
                // GeoJSON is [longitude, latitude].
                let line = part.filter { $0.count >= 2 }.map { GeoPoint(lat: $0[1], lon: $0[0]) }
                for point in line where point != flattened.last { flattened.append(point) }
                guard let first = line.first, let last = line.last else { continue }
                if joints.isEmpty { joints.append(first) }
                joints.append(last)
            }
            points = flattened
            self.joints = joints
        }
    }

    /// **Which of the two geography answers a 400 is** (ADR 2026-09-23 (c)).
    ///
    /// Matched on the provider's own words, measured against the live endpoint
    /// through the Worker on 2026-09-23 with public landmark coordinates:
    ///
    /// | request | answer |
    /// |---|---|
    /// | Taoyuan airport → Miyako airport | `No path could be found for input` |
    /// | Miyako town → Sunayama beach | `No suitable edges near location. Please check…` |
    ///
    /// Only the second is matched; **every other 400 stays `.noRoadHere`**, which
    /// is what all of them were before the split. If the provider ever rewords the
    /// off-network message, beaches go back to being crossings — the old
    /// behaviour, never a new wrong one — and `RouteReconstructionTests` pins the
    /// wording so that shows up as a red test, not as planes over beaches.
    static func verdict(for400 message: String) -> RouteReconstruction {
        message.localizedCaseInsensitiveContains("no suitable edges") ? .offTheRoadNetwork : .noRoadHere
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

    private func requestURL(for waypoints: [RouteMatchPoint], profile: String) -> URL? {
        guard var components = URLComponents(string: "\(config.baseURL)/v1/routing") else { return nil }
        // Latitude first — the opposite of the OSRM path this replaces.
        let coordinates = waypoints
            .map { String(format: "%.6f,%.6f", $0.lat, $0.lon) }
            .joined(separator: "|")
        var items = [
            URLQueryItem(name: "waypoints", value: coordinates),
            URLQueryItem(name: "mode", value: profile)
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
