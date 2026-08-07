import Foundation
import KamomeTrackingEngine

/// Minimal GPX 1.1 `<trkpt>` reader — a hosted app test cannot import the
/// CoreTests harness parser.
///
/// Split into its own file from `RecapDemoFilmTests.swift` (lint length only,
/// Chiu 2026-08-07) — self-contained, so the move needed no access changes.
final class GPXFilmParser: NSObject, XMLParserDelegate {
    private var points: [LocationSample] = []
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentTime: Double?
    private var textBuffer = ""
    private let iso = ISO8601DateFormatter()

    func parse(contentsOf url: URL) throws -> [LocationSample] {
        let parser = XMLParser(data: try Data(contentsOf: url))
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? NSError(domain: "GPXFilmParser", code: 1)
        }
        return points
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName: String?, attributes: [String: String] = [:]
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
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
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
