import AVFoundation
import CoreGraphics
import CoreText
@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeRouteMatching
import KamomeTrackingEngine
import KamomeTripComposer
import UniformTypeIdentifiers
import XCTest

/// Renders a **complete recap film** end to end for review — not a CI test.
///
/// Everything the shipped app would do: the real Perth → Margaret River GPX
/// replayed through the tracking engine, its live ∪ derived stops, the Modern
/// Minimal theme over MapLibre souvenir-map tiles, the 8-direction car, the
/// two-beat stop scenes with photo decks, title and end chrome, encoded to MP4.
///
/// Needs corridor tiles — the committed fixture crop covers ~20 km around
/// Margaret River, and this trip runs 290 km, so point `KAMOME_TILES_PATH` at a
/// corridor build (`Tests/Fixtures/tiles/generate_tiles.sh` with the bounds
/// widened; that artifact is far too large for git).
///
///   TEST_RUNNER_KAMOME_DEMO_FILM=1 \
///   TEST_RUNNER_KAMOME_TILES_PATH=/path/to/corridor.pmtiles \
///   TEST_RUNNER_KAMOME_RENDER_OUT=/path/to/out \
///   xcodebuild -scheme Kamome test -destination '…' \
///     -only-testing:KamomeTests/RecapDemoFilmTests
final class RecapDemoFilmTests: XCTestCase {
    private struct DeckResolver: RecapPhotoResolving {
        let images: [String: CGImage]
        func image(for ref: PhotoRef, targetPx: Int) -> CGImage? {
            if case let .asset(id) = ref { return images[id] }
            return nil
        }
    }

    func testRenderDemoFilm() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_DEMO_FILM"] == "1",
            "Manual demo render — set KAMOME_DEMO_FILM=1."
        )
        let config = try AppConfig.loadOrDie().export
        try await renderFilm(trip: try demoTrip(config: config), config: config, named: "kamome-demo-film")
    }

    /// Renders `trip` the way the shipped app would and prints where it landed.
    private func renderFilm(trip: RecapTrip, config: TrackingConfig.Export, named: String) async throws {
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config))
        let style = RecapStyle.modernMinimal

        // Stand-in photos: the simulator has no real library, and the deck beats
        // are the thing under review. One tile per selected photo.
        var images: [String: CGImage] = [:]
        for (index, ref) in trip.stops.flatMap(\.photos).enumerated() {
            if case let .asset(id) = ref { images[id] = try photoTile(index: index) }
        }

        let provider = try snapshotProvider(covering: trip)
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(style: style),
            overlay: RecapOverlayRenderer(style: style, resolver: DeckResolver(images: images)),
            style: style,
            widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
        )
        let exporter = RecapExporter(
            timeline: timeline, compositor: compositor, provider: provider, config: config
        )

        let outDir = outputDirectory()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let videoURL = outDir.appendingPathComponent("\(named).mp4")
        try? FileManager.default.removeItem(at: videoURL)

        let started = Date.now
        let output = try await exporter.export(videoURL: videoURL)
        let seconds = Date.now.timeIntervalSince(started)
        XCTAssertNotNil(output, "the demo film must render to completion")

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        let sizeMB = Double(
            (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int) ?? 0
        ) / 1e6
        print(String(
            format: "KAMOME_DEMO_FILM %@  %d stops · %d legs · %d frames · %.1fs video · %.1f MB · rendered in %.0fs",
            videoURL.path, trip.stops.count, trip.legs.count, timeline.frameCount, duration, sizeMB, seconds
        ))
    }

    // MARK: - Imported film (photos → legs → OSRM → recap)

    /// The **whole Replay MVP loop** in one artifact: geotagged photos →
    /// `ImportService` (per-leg segments) → OSRM `/route` reconstruction with the
    /// intermediate photos as via-waypoints → `RecapComposer` typed legs → film.
    ///
    /// This is where the honesty shows: the drives reconstruct against the road
    /// network and draw solid, while the coastal walk — never routed, because a
    /// car profile would snap it to the nearest street (PD-8) — draws dashed.
    /// Both are in the same frame, which is the point of PD-1.
    ///
    /// The trip is read from `Tests/Fixtures/trips/<name>.json` — one file per
    /// dogfood region, so a render is a fixture swap rather than a code change,
    /// and a real photo library can be dumped straight into that shape
    /// (`Tools/exif-to-fixture.sh`).
    ///
    /// Needs a live OSRM covering the region and tiles for it:
    ///
    ///   KAMOME_DEMO_FILM_IMPORT=iceland \
    ///   KAMOME_OSRM_BASE_URL=http://127.0.0.1:5100 \
    ///   KAMOME_TILES_PATH=~/kamome-osrm/tiles \
    ///   KAMOME_RENDER_OUT=/path/to/out
    func testRenderImportedFilm() async throws {
        let requested = ProcessInfo.processInfo.environment["KAMOME_DEMO_FILM_IMPORT"] ?? ""
        try XCTSkipUnless(
            !requested.isEmpty,
            "Manual demo render — set KAMOME_DEMO_FILM_IMPORT to a fixture name (e.g. iceland)."
        )
        let fixture = requested == "1" ? "margaret-river" : requested
        let full = try AppConfig.loadOrDie()
        let baseURL = ProcessInfo.processInfo.environment["KAMOME_OSRM_BASE_URL"] ?? "http://127.0.0.1:5100"
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let service = ImportService(
            repository: repository, config: full,
            matcher: RouteMatchService(
                repository: repository, config: full,
                reconstructor: OSRMRouteProvider(config: full.matching.withBaseURL(baseURL))
            )
        )

        let trip = try Self.tripFixture(named: fixture)
        let tripId = try await service.importTrip(title: trip.title, photos: trip.photos)
        let detail = try XCTUnwrap(try repository.detail(tripId: tripId))
        let legs = RecapComposer.legs(
            from: detail.segments, epsilonM: full.simplify.epsilonM, matchedEpsilonM: full.matching.displayEpsilonM
        )
        print("KAMOME_DEMO_FILM_IMPORT legs: " + legs.map { "\($0.mode.rawValue)/\($0.provenance)" }.joined(separator: ", "))

        let config = full.export
        var photosByStop: [String: [PhotoRef]] = [:]
        for stop in detail.stops {
            photosByStop[stop.id] = detail.photos
                .filter { $0.stopId == stop.id }
                .prefix(3)
                .map { PhotoRef.asset($0.phAssetId) }
        }
        let recap = try XCTUnwrap(RecapComposer.trip(
            trip: detail.trip, legs: legs, stops: detail.stops, stats: nil,
            photosByStop: photosByStop,
            deck: RecapDeck(photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS, labelLeadS: config.deckLabelLeadS),
            stopHoldS: config.stopHoldS
        ))
        try await renderFilm(trip: recap, config: config, named: "kamome-\(fixture)")
    }

    /// One dogfood region's trip, read from `Tests/Fixtures/trips/<name>.json`.
    ///
    /// Fixtures rather than literals so the four gate regions are data, and so a
    /// real photo library can be dumped into the same shape without touching
    /// this test (`Tools/exif-to-fixture.sh`).
    static func tripFixture(named name: String) throws -> (title: String, photos: [ImportPhoto]) {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/trips/\(name).json")
        let fixture = try JSONDecoder().decode(TripFixture.self, from: try Data(contentsOf: url))
        // Fixture times are offsets from the trip start, so a fixture reads as a
        // day rather than as a wall-clock date nobody can check.
        let start = 1_752_600_000.0
        return (
            fixture.title,
            fixture.photos.map {
                ImportPhoto(assetId: $0.id, timestamp: start + $0.offsetS, lat: $0.lat, lon: $0.lon)
            }
        )
    }

    // MARK: - Trip

    /// The committed day-1 GPX through the real engine, then the same composition
    /// the app performs: matched/simplified route, live ∪ derived stops, real
    /// stop names, photo-count-driven dwells.
    private func demoTrip(config: TrackingConfig.Export) throws -> RecapTrip {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/perth_margaret_river_day1.gpx")
        let samples = try GPXFilmParser().parse(contentsOf: fixture)
        let full = try AppConfig.loadOrDie()
        let engine = TrackingEngine(config: full, vehicle: .car)
        engine.start(at: try XCTUnwrap(samples.first).ts)
        for sample in samples { engine.process(sample) }
        engine.finish(at: try XCTUnwrap(samples.last).ts)

        let derived = StopDeriver.derive(segments: engine.segments, engineStops: engine.stops, config: full)
        let stops = (engine.stops + derived).sorted { $0.arrivedAt < $1.arrivedAt }
        let names = ["Mandurah", "Bunbury", "Busselton Jetty", "Margaret River"]
        let deck = RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS, labelLeadS: config.deckLabelLeadS
        )

        // One leg per engine segment, as the app now composes (typed-leg pass
        // 2026-07-26). This trip is real recorded GPS end to end, so every leg
        // is `.recorded` and draws solid — the dashed treatment is exercised by
        // the imported film below, where it belongs.
        let legs = engine.segments.compactMap { segment -> RecapTrip.Leg? in
            let points = segment.points.map { Simplifier.Point(lat: $0.lat, lon: $0.lon) }
            let simplified = Simplifier.douglasPeucker(points, epsilonM: full.simplify.epsilonM)
                .map { RecapCoordinate(lat: $0.lat, lon: $0.lon) }
            guard simplified.count >= 2 else { return nil }
            return RecapTrip.Leg(coordinates: simplified, mode: segment.mode, provenance: .recorded)
        }

        let tripStops = stops.enumerated().map { index, stop -> RecapTrip.Stop in
            let photos = (0..<3).map { PhotoRef.asset("stop\(index)-photo\($0)") }
            return RecapTrip.Stop(
                coordinate: RecapCoordinate(lat: stop.lat, lon: stop.lon),
                name: index < names.count ? names[index] : "停留 \(index + 1)",
                dayLabel: "Day 1", detail: nil, photos: photos,
                dwellS: deck.dwellS(photoCount: photos.count)
            )
        }
        return RecapTrip(
            legs: legs, stops: tripStops,
            title: "Perth → Margaret River", subtitle: "Day 1 · 291 km",
            statsLines: ["291 km · \(tripStops.count) 停留", "5.8 小時"],
            callToAction: "Record your own journey"
        )
    }

    // MARK: - Providers and assets

    private func snapshotProvider(covering trip: RecapTrip) throws -> MapRenderer {
        #if canImport(MapLibre)
        let bounds = try XCTUnwrap(GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) }))
        guard let tiles = RecapMapTiles.tilesURL(covering: bounds) else {
            XCTFail("no tiles covering the trip — set TEST_RUNNER_KAMOME_TILES_PATH")
            return MapKitSnapshotProvider()
        }
        let styleURL = try RecapMapStyle.resolvedStyleURL(
            styleResource: RecapMapTiles.styleResource, tilesURL: tiles
        )
        return MapLibreSnapshotProvider(styleURL: styleURL)
        #else
        return MapKitSnapshotProvider()
        #endif
    }

    private func outputDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["KAMOME_RENDER_OUT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("kamome-demo-film", isDirectory: true)
    }

    /// A stand-in photo: a diagonal gradient with a big index, so each deck slot
    /// is visibly a different picture.
    private func photoTile(index: Int) throws -> CGImage {
        let side = 900
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let palettes: [(CGColor, CGColor)] = [
            (CGColor(srgbRed: 0.20, green: 0.45, blue: 0.70, alpha: 1),
             CGColor(srgbRed: 0.10, green: 0.22, blue: 0.35, alpha: 1)),
            (CGColor(srgbRed: 0.75, green: 0.45, blue: 0.30, alpha: 1),
             CGColor(srgbRed: 0.38, green: 0.22, blue: 0.15, alpha: 1)),
            (CGColor(srgbRed: 0.35, green: 0.60, blue: 0.40, alpha: 1),
             CGColor(srgbRed: 0.18, green: 0.30, blue: 0.20, alpha: 1))
        ]
        let (top, bottom) = palettes[index % palettes.count]
        let gradient = try XCTUnwrap(CGGradient(
            colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]
        ))
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 300, nil)
        let attrs = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85)
        ] as CFDictionary
        let line = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(kCFAllocatorDefault, "\(index + 1)" as CFString, attrs)!
        )
        let bounds = CTLineGetImageBounds(line, context)
        context.textPosition = CGPoint(x: (CGFloat(side) - bounds.width) / 2, y: (CGFloat(side) - bounds.height) / 2)
        CTLineDraw(line, context)
        return try XCTUnwrap(context.makeImage())
    }
}

/// Minimal GPX 1.1 `<trkpt>` reader — a hosted app test cannot import the
/// CoreTests harness parser.
private final class GPXFilmParser: NSObject, XMLParserDelegate {
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

/// On-disk shape of `Tests/Fixtures/trips/*.json` — place and time only, which
/// is exactly what `ImportService` sees on device.
private struct TripFixture: Decodable {
    struct Photo: Decodable {
        let id: String
        /// Seconds from the trip's first photo.
        let offsetS: Double
        let lat: Double
        let lon: Double

        enum CodingKeys: String, CodingKey {
            case id, lat, lon
            case offsetS = "t"
        }
    }

    let title: String
    let photos: [Photo]
}
