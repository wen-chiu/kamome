import Foundation
import KamomeConfig
import KamomeTrackingEngine

/// Boundary for route *reconstruction* — the sibling of `RouteMatchProviding`
/// for traces too sparse to map-match (typed-leg pass 2026-07-26).
///
/// **Why a second boundary rather than a second implementation of the first.**
/// The two answer different questions. `/match` asks "which road were these
/// dense GPS fixes on?" and needs the trace to be a near-continuous sample of
/// the drive. A photo-EXIF leg is nothing like that: three or four positions
/// hours apart, which OSRM's Hidden-Markov matcher will either reject outright
/// or match to an arbitrary road. The question there is "what is the plausible
/// driving route *through* these places?" — a routing query with the photos as
/// via-waypoints (PD-3). Same return type, because the caller does the same
/// thing with both: store the geometry, or keep the raw leg and render it
/// inferred (PD-2).
///
/// Returns nil when no plausible route exists (server disabled, too few
/// waypoints, sanity gate rejected the answer) — never a guess.
public protocol RouteReconstructing: Sendable {
    func route(_ waypoints: [RouteMatchPoint]) async throws -> RouteMatchOutcome?
}

/// OSRM `/route` client. Like `OSRMMatchProvider`, every OSRM-specific fact —
/// URL shape, response schema, waypoint limit — is confined to this one file.
///
/// With `matching.base_url` empty this provider is a no-network no-op returning
/// nil, so simulator runs and CI never need a server.
public struct OSRMRouteProvider: RouteReconstructing {
    /// Injectable so tests replay recorded OSRM responses without a live server.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let config: TrackingConfig.Matching
    private let transport: Transport

    public init(config: TrackingConfig.Matching, transport: Transport? = nil) {
        self.config = config
        self.transport = transport ?? { request in
            try await URLSession.shared.data(for: request)
        }
    }

    /// One request, with the two failures that matter told apart in the log.
    ///
    /// Returns nil for OSRM's own "these waypoints cannot be joined by road"
    /// (`NoRoute` / `NoSegment`, answered as HTTP 400) — a clean keep-raw verdict,
    /// and what a leg across water correctly gets. **Throws** for anything else,
    /// because a transport failure is not a verdict about the geography: on a
    /// dogfood build it is an unreachable Mac, an ATS refusal, a denied
    /// local-network prompt or the wrong Wi-Fi. All four produce an identical
    /// all-dashed film and completely different log lines.
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
        guard let http = response as? HTTPURLResponse, http.statusCode != 200 else { return data }
        if let body = try? JSONDecoder().decode(Response.self, from: data), body.code != "Ok" {
            KamomeLog.routing.notice(
                "route: OSRM said \(body.code, privacy: .public) (HTTP \(http.statusCode)) — leg stays raw"
            )
            return nil
        }
        // 429 is told apart from every other refusal because it is the one that
        // says "later" rather than "no" — a hosted provider will produce it and
        // a LAN OSRM never did (2026-08-15).
        if http.statusCode == 429 {
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init)
            KamomeLog.routing.error(
                "route: RATE LIMITED by \(config.baseURL, privacy: .public), retry after \(retryAfter ?? -1)s"
            )
            throw RouteProviderFailure.rateLimited(retryAfterS: retryAfter)
        }
        KamomeLog.routing.error("route: HTTP \(http.statusCode) from \(config.baseURL, privacy: .public)")
        throw RouteProviderFailure.refused(status: http.statusCode)
    }

    /// Every `return nil` here is a leg that will draw dashed, and every one of
    /// them used to be indistinguishable from the others in the finished film
    /// (2026-08-01). They are now named in the log as they happen — "disabled",
    /// "NoSegment", "detour 4.1×" and a transport failure are four very different
    /// problems with one identical symptom.
    public func route(_ waypoints: [RouteMatchPoint]) async throws -> RouteMatchOutcome? {
        guard !config.baseURL.isEmpty else {
            KamomeLog.routing.notice("route: skipped — matching.base_url is empty, so the leg stays raw (PD-2)")
            return nil
        }
        let thinned = Self.thinned(waypoints, minSpacingM: config.routeWaypointMinSpacingM, limit: config.chunkSize)
        guard thinned.count >= 2, let url = requestURL(for: thinned) else {
            KamomeLog.routing.notice("route: skipped — \(thinned.count) usable waypoints after thinning")
            return nil
        }

        guard let data = try await fetch(url) else { return nil }
        let body = try JSONDecoder().decode(Response.self, from: data)
        guard body.code == "Ok", let route = body.routes?.first else {
            KamomeLog.routing.notice("route: OSRM said \(body.code, privacy: .public) — leg stays raw")
            return nil
        }
        let geometry = EncodedPolyline.decode(route.geometry)
        guard geometry.count >= 2 else {
            KamomeLog.routing.notice("route: OSRM returned \(geometry.count) points — leg stays raw")
            return nil
        }

        // The sanity gate (PD-3 outlier protection). `/route` always answers
        // *something* drivable, so without this a single wrong EXIF fix would
        // silently produce a confident 300 km detour drawn as real road.
        let straightM = Self.straightLineM(thinned)
        guard straightM > 0 else { return nil }
        guard route.distance <= straightM * config.routeMaxDetourRatio else {
            KamomeLog.routing.notice("""
                route: REJECTED by the detour gate — \(route.distance / 1000, format: .fixed(precision: 1)) km routed \
                vs \(straightM / 1000, format: .fixed(precision: 1)) km straight \
                (\(route.distance / straightM, format: .fixed(precision: 1))× > \
                \(config.routeMaxDetourRatio, format: .fixed(precision: 1))×) — leg stays raw (PD-3)
                """)
            return nil
        }
        KamomeLog.routing.notice(
            "route: reconstructed \(route.distance / 1000, format: .fixed(precision: 1)) km from \(thinned.count) waypoints"
        )

        // `/route` reports no confidence. Passing the gate is the verdict:
        // the caller stores the geometry, which is what marks the leg
        // reconstructed rather than inferred.
        return RouteMatchOutcome(geometry: geometry, confidence: 1)
    }

    // MARK: - Waypoint hygiene

    /// Drops intermediate waypoints that sit within `minSpacingM` of the last
    /// kept one, then caps the list at OSRM's per-request location limit by
    /// keeping an evenly spread subset. The **endpoints are never dropped** —
    /// they are the stop centroids the leg is defined by; only the photo
    /// evidence in between is thinned.
    static func thinned(_ waypoints: [RouteMatchPoint], minSpacingM: Double, limit: Int) -> [RouteMatchPoint] {
        guard waypoints.count > 2 else { return waypoints }
        let first = waypoints[0]
        let last = waypoints[waypoints.count - 1]

        var kept: [RouteMatchPoint] = [first]
        for waypoint in waypoints[1..<(waypoints.count - 1)] {
            let previous = kept[kept.count - 1]
            let spacing = Geo.distanceM(latA: previous.lat, lonA: previous.lon, latB: waypoint.lat, lonB: waypoint.lon)
            if spacing >= minSpacingM { kept.append(waypoint) }
        }
        kept.append(last)

        guard limit >= 2, kept.count > limit else { return kept }
        // Evenly spread: keep both ends and sample the interior.
        let interiorBudget = limit - 2
        let interior = kept[1..<(kept.count - 1)]
        let stride = Double(interior.count) / Double(max(interiorBudget, 1))
        var capped: [RouteMatchPoint] = [kept[0]]
        for slot in 0..<interiorBudget {
            let index = Int((Double(slot) + 0.5) * stride)
            capped.append(interior[interior.startIndex + min(index, interior.count - 1)])
        }
        capped.append(kept[kept.count - 1])
        return capped
    }

    /// Total great-circle length through the waypoints — the floor any honest
    /// road route must be at least as long as.
    static func straightLineM(_ waypoints: [RouteMatchPoint]) -> Double {
        zip(waypoints, waypoints.dropFirst()).reduce(0.0) { sum, pair in
            sum + Geo.distanceM(latA: pair.0.lat, lonA: pair.0.lon, latB: pair.1.lat, lonB: pair.1.lon)
        }
    }

    // MARK: - OSRM wire format

    private struct Response: Decodable {
        struct Route: Decodable {
            let geometry: String
            /// Road distance in meters — the sanity gate's input.
            let distance: Double
        }

        let code: String
        let routes: [Route]?
    }

    private func requestURL(for waypoints: [RouteMatchPoint]) -> URL? {
        let coordinates = waypoints
            .map { String(format: "%.6f,%.6f", $0.lon, $0.lat) }
            .joined(separator: ";")
        // `route_waypoint_radius_m`, not the GPS-accuracy floor — see the
        // tunable's note: photos sit beside roads, not on them.
        let radiuses = waypoints
            .map { String(Int(max($0.hAccM ?? 0, config.routeWaypointRadiusM))) }
            .joined(separator: ";")
        let query = "geometries=polyline&overview=full&steps=false&radiuses=\(radiuses)"
        return URL(string: "\(config.baseURL)/route/v1/driving/\(coordinates)?\(query)")
    }
}
