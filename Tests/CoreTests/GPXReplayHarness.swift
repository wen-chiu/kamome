import Foundation
import KamomeConfig
import KamomeTrackingEngine
import XCTest

/// Feeds a GPX fixture through the real TrackingEngine (spec §7 Phase 1:
/// "GPX replay harness that feeds fixtures through the real engine in tests").
enum GPXReplay {
    static func fixturesURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/CoreTests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent("Fixtures")
    }

    static func loadConfig() throws -> TrackingConfig {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
        return try TrackingConfigLoader.load(contentsOf: url)
    }

    static func samples(fixture: String) throws -> [LocationSample] {
        let url = fixturesURL().appendingPathComponent(fixture)
        let parser = GPXTrackParser()
        return try parser.parse(contentsOf: url)
    }

    /// Replays a fixture start-to-finish; GPX carries no speed, so the engine
    /// derives it from displacement — exactly the degraded-GPS code path.
    static func run(fixture: String, vehicle: VehicleType = .car) throws -> TrackingEngine {
        let points = try samples(fixture: fixture)
        let engine = TrackingEngine(config: try loadConfig(), vehicle: vehicle)
        guard let first = points.first, let last = points.last else {
            XCTFail("fixture \(fixture) is empty")
            return engine
        }
        engine.start(at: first.ts)
        for point in points {
            engine.process(point)
        }
        engine.finish(at: last.ts)
        return engine
    }
}

/// Minimal GPX 1.1 <trkpt> reader — fixtures only, not a general GPX codec.
final class GPXTrackParser: NSObject, XMLParserDelegate {
    private var points: [LocationSample] = []
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentTime: Double?
    private var currentElement = ""
    private var textBuffer = ""
    private let iso = ISO8601DateFormatter()

    func parse(contentsOf url: URL) throws -> [LocationSample] {
        let data = try Data(contentsOf: url)
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? NSError(domain: "GPXTrackParser", code: 1)
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
        currentElement = elementName
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
        currentElement = ""
    }
}
