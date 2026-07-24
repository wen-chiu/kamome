import Foundation
import KamomeConfig
import KamomeRouteMatching
import KamomeTrackingEngine
import XCTest

/// §4.4 recorded-response gate (handoff P3.5 §1 item 4): one real OSRM
/// `/match` response for a perth-fixture drive segment, checked into
/// `Tests/Fixtures/osrm/` and replayed through `OSRMMatchProvider`'s
/// injectable transport — so matching stays asserted in CI with no live
/// server, no network, bit-stable.
///
/// Capture and replay share `recordedSegment(config:)`, so the trace the CI
/// test builds is by construction the trace the fixture was recorded for.
/// Re-capture (server setup in `Docs/osrm-setup.md`):
///
///   TEST_RUNNER_KAMOME_OSRM_CAPTURE=1 → testCaptureRecordedFixture hits the
///   live server (KAMOME_OSRM_BASE_URL, default the perth port from the
///   setup doc) and rewrites the fixture file.
final class OSRMRecordedFixtureTests: XCTestCase {
    /// The captured segment: the first perth-fixture drive segment that fits
    /// in a single `/match` request (≤ chunk_size locations), so the fixture
    /// is exactly one request/response pair. Falls back to the first drive
    /// segment's leading chunk if the engine ever stops producing one — the
    /// name changes with it, failing the replay test loudly until re-capture.
    static func recordedSegment(
        config: TrackingConfig.Matching
    ) throws -> (name: String, trace: [RouteMatchPoint]) {
        let engine = try GPXReplay.run(fixture: "perth_margaret_river_day1.gpx")
        let drives = engine.segments.filter { $0.mode == .drive }
        let trace: (TrackingEngine.Segment) -> [RouteMatchPoint] = { segment in
            segment.points.map { RouteMatchPoint(ts: $0.ts, lat: $0.lat, lon: $0.lon, hAccM: $0.hAccM) }
        }
        if let index = drives.firstIndex(where: { (2...config.chunkSize).contains($0.points.count) }) {
            return ("perth_day1_drive\(index + 1)", trace(drives[index]))
        }
        guard let first = drives.first else {
            throw XCTSkip("perth fixture produced no drive segments")
        }
        return ("perth_day1_drive1_first\(config.chunkSize)", Array(trace(first).prefix(config.chunkSize)))
    }

    private static func fixtureURL(name: String) -> URL {
        GPXReplay.fixturesURL().appendingPathComponent("osrm/\(name).json")
    }

    /// Independent mirror of the OSRM wire format — deliberately not the
    /// provider's private decoder, so a schema drift breaks the comparison.
    private struct RecordedResponse: Decodable {
        struct Matching: Decodable {
            let confidence: Double
            let geometry: String
        }

        let code: String
        let matchings: [Matching]?
    }

    // MARK: - CI replay

    func testPerthDriveSegmentReplayedThroughTransportStaysOnRecordedPolyline() async throws {
        let config = try GPXReplay.loadConfig().matching
        // The transport is stubbed, so the URL is never contacted; a non-empty
        // base is still required for the provider to run at all.
        let testConfig = TrackingConfig.Matching(
            baseURL: "http://recorded.invalid",
            chunkSize: config.chunkSize,
            confidenceMin: config.confidenceMin,
            radiusM: config.radiusM,
            timeoutS: config.timeoutS,
            displayEpsilonM: config.displayEpsilonM
        )
        let (name, trace) = try Self.recordedSegment(config: testConfig)
        let fixtureURL = Self.fixtureURL(name: name)
        guard let data = try? Data(contentsOf: fixtureURL) else {
            XCTFail("missing fixture \(fixtureURL.path) — re-capture with TEST_RUNNER_KAMOME_OSRM_CAPTURE=1")
            return
        }
        let recorded = try JSONDecoder().decode(RecordedResponse.self, from: data)
        XCTAssertEqual(recorded.code, "Ok")
        let matchings = try XCTUnwrap(recorded.matchings)
        XCTAssertFalse(matchings.isEmpty)

        let requests = Recorder()
        let provider = OSRMMatchProvider(config: testConfig) { request in
            await requests.record(request.url)
            let http = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (data, http)
        }
        let outcome = try await provider.match(trace)

        // One segment, one request — the invariant the capture relies on.
        let urls = await requests.urls
        XCTAssertEqual(urls.count, 1)
        let url = try XCTUnwrap(urls.first?.absoluteString)
        XCTAssertTrue(url.hasPrefix("http://recorded.invalid/match/v1/driving/"))
        XCTAssertEqual(
            url.components(separatedBy: "/match/v1/driving/").last?
                .components(separatedBy: "?").first?
                .components(separatedBy: ";").count,
            trace.count,
            "request must carry one coordinate per trace point"
        )

        // The §4.4 contract on a real recorded response: confident match, and
        // the provider's decoded geometry stays on the recorded polyline to
        // within the codec's precision (1e-5 deg ≈ 1.1 m).
        let matched = try XCTUnwrap(outcome)
        XCTAssertGreaterThanOrEqual(matched.confidence, testConfig.confidenceMin)
        let expected = matchings.flatMap { EncodedPolyline.decode($0.geometry) }
        XCTAssertEqual(matched.geometry.count, expected.count)
        for (actual, reference) in zip(matched.geometry, expected) {
            XCTAssertEqual(actual.lat, reference.lat, accuracy: 1e-5)
            XCTAssertEqual(actual.lon, reference.lon, accuracy: 1e-5)
        }
    }

    // MARK: - Capture (manual, live server)

    func testCaptureRecordedFixture() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_OSRM_CAPTURE"] == "1",
            "manual capture — set TEST_RUNNER_KAMOME_OSRM_CAPTURE=1 with a live OSRM server"
        )
        let loaded = try GPXReplay.loadConfig().matching
        let baseURL = ProcessInfo.processInfo.environment["KAMOME_OSRM_BASE_URL"] ?? "http://127.0.0.1:5001"
        let config = TrackingConfig.Matching(
            baseURL: baseURL,
            chunkSize: loaded.chunkSize,
            confidenceMin: loaded.confidenceMin,
            radiusM: loaded.radiusM,
            timeoutS: loaded.timeoutS,
            displayEpsilonM: loaded.displayEpsilonM
        )
        let (name, trace) = try Self.recordedSegment(config: config)
        print("KAMOME_OSRM_CAPTURE segment \(name): \(trace.count) trace points → \(baseURL)")

        let responses = Recorder()
        let provider = OSRMMatchProvider(config: config) { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            await responses.record(data)
            return (data, response)
        }
        let outcome = try await provider.match(trace)

        let bodies = await responses.bodies
        XCTAssertEqual(bodies.count, 1, "the captured segment must fit one /match request")
        let matched = try XCTUnwrap(outcome, "live capture must clear confidence_min — pick a denser segment")
        let destination = Self.fixtureURL(name: name)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try XCTUnwrap(bodies.first).write(to: destination)
        print(String(
            format: "KAMOME_OSRM_CAPTURE confidence %.3f, %d geometry points → %@",
            matched.confidence, matched.geometry.count, destination.path
        ))
    }
}

/// Transport observations cross the @Sendable async closure boundary; an
/// actor keeps them data-race free without the lock boilerplate.
private actor Recorder {
    private(set) var urls: [URL] = []
    private(set) var bodies: [Data] = []

    func record(_ url: URL?) {
        if let url {
            urls.append(url)
        }
    }

    func record(_ body: Data) {
        bodies.append(body)
    }
}
