@testable import Kamome
import KamomeConfig
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import KamomeTripComposer
import XCTest

/// Manual §4.4 end-to-end validation (handoff P3.5 §1): replays the perth GPX
/// fixture through the real engine, saves it as a completed trip, and runs the
/// real S5 export pipeline — `RecapModel` → `RouteMatchService` → OSRM →
/// `RecapComposer` snapped-geometry preference → `RecapExporter`. Skipped
/// unless its env var is set: it needs wall time, Apple Maps tiles, and — for
/// the matched case — a live OSRM server at `matching.base_url`
/// (`Docs/osrm-setup.md`; the bundled default `""` exports raw geometry, which
/// is the "before" half of the §1 comparison).
///
///   TEST_RUNNER_KAMOME_MATCHING_E2E=1  → run
///   TEST_RUNNER_KAMOME_E2E_OUT=/tmp    → copy the exported MP4 to the host
final class RecapMatchingE2ETests: XCTestCase {
    @MainActor
    func testExportPerthFixtureRecapThroughAppPipeline() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_MATCHING_E2E"] == "1",
            "manual end-to-end run — set TEST_RUNNER_KAMOME_MATCHING_E2E=1"
        )
        let config = AppConfig.loadOrDie()
        print("KAMOME_E2E matching.base_url = \"\(config.matching.baseURL)\""
            + (config.matching.baseURL.isEmpty ? " (disabled → raw geometry export)" : ""))

        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-e2e-\(UUID().uuidString).sqlite")
        let repository = TripRepository(database: try AppDatabase.onDisk(path: dbURL.path))
        let tripId = try seedPerthFixtureTrip(into: repository, config: config)

        let model = RecapModel(tripId: tripId, config: config, repository: repository)
        model.format = .mp4
        model.startExport()

        let deadline = Date.now.addingTimeInterval(600)
        while Date.now < deadline {
            if case .rendering = model.phase {
                try await Task.sleep(nanoseconds: 500_000_000)
            } else {
                break
            }
        }
        guard case .finished(let shareURL, let renderSeconds) = model.phase else {
            XCTFail("export did not finish: \(model.phase)")
            return
        }
        print(String(format: "KAMOME_E2E rendered in %.1f s → %@", renderSeconds, shareURL.path))

        // Per-segment matching report: which segments got snapped geometry.
        let detail = try XCTUnwrap(repository.detail(tripId: tripId))
        for (segment, points) in detail.segments {
            let matched = segment.matchedPolyline.map { "matched \(EncodedPolyline.decode($0).count) pts" }
                ?? "raw"
            print("KAMOME_E2E segment \(segment.mode): \(points.count) raw pts → \(matched)")
        }
        if !config.matching.baseURL.isEmpty {
            let drives = detail.segments.filter { $0.segment.mode == TransportMode.drive.rawValue }
            XCTAssertFalse(drives.isEmpty)
            XCTAssertTrue(
                drives.allSatisfy { $0.segment.matchedPolyline != nil },
                "every drive segment should match against a live server on the dense fixture"
            )
        }

        if let out = ProcessInfo.processInfo.environment["KAMOME_E2E_OUT"] {
            let suffix = config.matching.baseURL.isEmpty ? "raw" : "matched"
            let destination = URL(fileURLWithPath: out, isDirectory: true)
                .appendingPathComponent("kamome-e2e-\(suffix).mp4")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: shareURL, to: destination)
            print("KAMOME_E2E copied to \(destination.path)")
        }
    }

    // MARK: - Seeding (perth fixture → completed trip rows)

    /// Mirrors what `TrackingSession.end()` persists, sourced from the same
    /// GPX replay CoreTests use: real engine segmentation, live ∪ derived
    /// stops. The `-demo-seed` trip is deliberately not used here — its
    /// heavily thinned route is below `matching.confidence_min` by design
    /// (sparse traces keep raw geometry; do not lower the floor).
    private func seedPerthFixtureTrip(into repository: TripRepository, config: TrackingConfig) throws -> String {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/AppTests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent("Fixtures/perth_margaret_river_day1.gpx")
        let samples = try GPXFixtureParser().parse(contentsOf: fixtureURL)
        let first = try XCTUnwrap(samples.first)
        let last = try XCTUnwrap(samples.last)

        let engine = TrackingEngine(config: config, vehicle: .car)
        engine.start(at: first.ts)
        for sample in samples {
            engine.process(sample)
        }
        engine.finish(at: last.ts)

        let derived = StopDeriver.derive(segments: engine.segments, engineStops: engine.stops, config: config)
        let stops = (engine.stops + derived).sorted { $0.arrivedAt < $1.arrivedAt }

        let tripId = try repository.saveCompletedTrip(
            title: "Perth → Margaret River",
            startedAt: first.ts,
            endedAt: last.ts,
            segments: engine.segments.map { segment in
                TripRepository.NewSegment(
                    mode: segment.mode.rawValue,
                    startedAt: segment.startedAt,
                    endedAt: segment.endedAt,
                    points: segment.points.map {
                        TripRepository.NewTrackpoint(ts: $0.ts, lat: $0.lat, lon: $0.lon, hAcc: $0.hAccM)
                    }
                )
            },
            stops: stops.map {
                TripRepository.NewStop(
                    lat: $0.lat, lon: $0.lon,
                    arrivedAt: $0.arrivedAt, departedAt: $0.departedAt,
                    kind: $0.kind.rawValue
                )
            }
        )

        // Same stop names as the P3 demo artifact, in arrival order; the
        // geocoder is skipped for determinism (DemoSeeder precedent).
        let names = ["Mandurah", "Bunbury", "Busselton Jetty", "Margaret River"]
        if let detail = try repository.detail(tripId: tripId) {
            for (record, name) in zip(detail.stops, names) {
                try repository.setStopName(stopId: record.id, name: name)
            }
        }

        if let statsJson = tripStats(segments: engine.segments, stopCount: stops.count).jsonString() {
            try repository.updateTripStats(tripId: tripId, statsJson: statsJson)
        }
        return tripId
    }

    private func tripStats(segments: [TrackingEngine.Segment], stopCount: Int) -> TripStats {
        var distanceM = 0.0
        var driveS = 0.0
        var walkS = 0.0
        var topSpeedMps = 0.0
        for segment in segments {
            for (from, to) in zip(segment.points, segment.points.dropFirst()) {
                let legM = Geo.distanceM(latA: from.lat, lonA: from.lon, latB: to.lat, lonB: to.lon)
                distanceM += legM
                let legS = to.ts - from.ts
                if legS > 0 {
                    topSpeedMps = max(topSpeedMps, legM / legS)
                }
            }
            let duration = (segment.endedAt ?? segment.startedAt) - segment.startedAt
            switch segment.mode {
            case .walk: walkS += duration
            default: driveS += duration
            }
        }
        return TripStats(
            distanceM: distanceM,
            driveS: driveS,
            walkS: walkS,
            stopCount: stopCount,
            topSpeedKmh: topSpeedMps * 3.6
        )
    }
}

/// Minimal GPX 1.1 `<trkpt>` reader — a private mirror of the CoreTests
/// harness parser (`GPXReplayHarness.swift`), which a hosted app test cannot
/// import. Fixtures only.
private final class GPXFixtureParser: NSObject, XMLParserDelegate {
    private var points: [LocationSample] = []
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentTime: Double?
    private var textBuffer = ""
    private let iso = ISO8601DateFormatter()

    func parse(contentsOf url: URL) throws -> [LocationSample] {
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? NSError(domain: "GPXFixtureParser", code: 1)
        }
        return points
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        textBuffer = ""
        if elementName == "trkpt" {
            currentLat = attributes["lat"].flatMap(Double.init)
            currentLon = attributes["lon"].flatMap(Double.init)
            currentTime = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName {
        case "time":
            currentTime = iso.date(from: textBuffer.trimmingCharacters(in: .whitespacesAndNewlines))?
                .timeIntervalSince1970
        case "trkpt":
            if let lat = currentLat, let lon = currentLon, let ts = currentTime {
                points.append(LocationSample(ts: ts, lat: lat, lon: lon, hAccM: 10))
            }
        default:
            break
        }
    }
}
