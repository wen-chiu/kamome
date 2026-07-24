import Foundation
import KamomeConfig

/// OSRM `/match` client (§4.4). All OSRM-specific knowledge — URL shape,
/// response schema, chunking limits — lives in this one file, mirroring how
/// `import MapKit` is confined to `MapKitSnapshotProvider.swift`.
///
/// Server setup (Docker compose, Taiwan + Australia extracts):
/// `Docs/osrm-setup.md`. With `matching.base_url` empty this provider is a
/// no-network no-op returning nil, so simulator runs and CI never need a
/// server.
public struct OSRMMatchProvider: RouteMatchProviding {
    /// Injectable so tests replay recorded OSRM responses (P4 gate: matching
    /// asserted in CI without a live server).
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let config: TrackingConfig.Matching
    private let transport: Transport

    public init(config: TrackingConfig.Matching, transport: Transport? = nil) {
        self.config = config
        self.transport = transport ?? { request in
            try await URLSession.shared.data(for: request)
        }
    }

    public func match(_ points: [RouteMatchPoint]) async throws -> RouteMatchOutcome? {
        guard !config.baseURL.isEmpty, points.count >= 2 else { return nil }

        var geometry: [GeoPoint] = []
        var worstConfidence = 1.0
        for chunk in chunked(points) {
            guard let matched = try await matchChunk(chunk) else { return nil }
            worstConfidence = min(worstConfidence, matched.confidence)
            // Chunks are cut without overlap; adjacent matched positions make
            // the stitch visually continuous. Drop an exactly-repeated joint.
            if matched.geometry.first == geometry.last {
                geometry.append(contentsOf: matched.geometry.dropFirst())
            } else {
                geometry.append(contentsOf: matched.geometry)
            }
        }

        // Segment-level gate (§4.4): one low-confidence stretch means the
        // whole segment renders as raw/"inferred" rather than part-invented.
        guard worstConfidence >= config.confidenceMin, geometry.count >= 2 else { return nil }
        return RouteMatchOutcome(geometry: geometry, confidence: worstConfidence)
    }

    // MARK: - OSRM wire format

    private struct Response: Decodable {
        struct Matching: Decodable {
            let confidence: Double
            let geometry: String
        }

        let code: String
        let matchings: [Matching]?
    }

    private func matchChunk(_ points: [RouteMatchPoint]) async throws -> RouteMatchOutcome? {
        guard points.count >= 2, let url = requestURL(for: points) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = config.timeoutS

        let (data, response) = try await transport(request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // OSRM answers 400 with code "NoMatch"/"NoSegment" for unmatchable
            // traces — that is a clean "keep raw geometry", not an error.
            if let body = try? JSONDecoder().decode(Response.self, from: data), body.code != "Ok" {
                return nil
            }
            throw URLError(.badServerResponse)
        }

        let body = try JSONDecoder().decode(Response.self, from: data)
        guard body.code == "Ok", let matchings = body.matchings, !matchings.isEmpty else { return nil }

        // A gap in the trace splits the response into several matchings; in
        // trace order their geometries concatenate into one segment polyline.
        let geometry = matchings.flatMap { EncodedPolyline.decode($0.geometry) }
        guard let confidence = matchings.map(\.confidence).min() else { return nil }
        return RouteMatchOutcome(geometry: geometry, confidence: confidence)
    }

    private func requestURL(for points: [RouteMatchPoint]) -> URL? {
        let coordinates = points
            .map { String(format: "%.6f,%.6f", $0.lon, $0.lat) }
            .joined(separator: ";")
        let timestamps = points
            .map { String(Int($0.ts)) }
            .joined(separator: ";")
        let radiuses = points
            .map { String(Int(max($0.hAccM ?? config.radiusM, config.radiusM))) }
            .joined(separator: ";")
        let query = "geometries=polyline&overview=full&tidy=true"
            + "&timestamps=\(timestamps)&radiuses=\(radiuses)"
        return URL(string: "\(config.baseURL)/match/v1/driving/\(coordinates)?\(query)")
    }

    private func chunked(_ points: [RouteMatchPoint]) -> [[RouteMatchPoint]] {
        stride(from: 0, to: points.count, by: config.chunkSize)
            .map { Array(points[$0..<min($0 + config.chunkSize, points.count)]) }
            // A trailing 1-point chunk can't be matched (and growing the
            // previous chunk would break OSRM's default 100-location cap);
            // one dropped trackpoint is invisible at recap zoom.
            .filter { $0.count >= 2 }
    }
}
