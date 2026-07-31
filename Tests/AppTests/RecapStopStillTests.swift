import CoreGraphics
import ImageIO
@testable import Kamome
import KamomeConfig
import KamomeExportEngine
import UniformTypeIdentifiers
import XCTest

/// Renders **one stop** of a real imported trip — not the film. Manual review
/// harness, env-gated, never CI.
///
/// A stop's presentation is a still-frame question (does the photo dominate? does
/// the map still read around it? is the type a headline or an annotation?), and
/// answering it with a 90-second MP4 render costs minutes and settles nothing.
/// This takes the same pipeline the exporter uses — imported trip → OSRM
/// reconstruction → `LinearTimeline` → `FrameCompositor` over the real MapLibre
/// souvenir map — and writes the single frame where the stop's photo deck is most
/// open.
///
/// Real photographs matter here: a synthetic gradient tile cannot tell you
/// whether a white keyline and a drop shadow read as a photo card. Point
/// `KAMOME_STOP_PHOTOS` at a folder of images and they are dealt into the deck in
/// filename order; without it the deck falls back to generated tiles.
///
///   TEST_RUNNER_KAMOME_STOP_STILL=iceland \
///   TEST_RUNNER_KAMOME_OSRM_BASE_URL=http://127.0.0.1:5100 \
///   TEST_RUNNER_KAMOME_TILES_PATH=$HOME/kamome-osrm/tiles \
///   TEST_RUNNER_KAMOME_STOP_PHOTOS=/path/to/jpegs \
///   TEST_RUNNER_KAMOME_RENDER_OUT=/path/to/out \
///   xcodebuild -scheme Kamome test -destination '…' \
///     -only-testing:KamomeTests/RecapStopStillTests
final class RecapStopStillTests: XCTestCase {
    /// Deals a folder of real images into the deck by `PhotoRef` order, so each
    /// slot of a stop is a different photograph. Falls back to nil (the deck
    /// still blooms its matte) when the folder is missing or short.
    private struct FolderResolver: RecapPhotoResolving {
        let images: [String: CGImage]
        func image(for ref: PhotoRef, targetPx: Int) -> CGImage? {
            if case let .asset(id) = ref { return images[id] }
            return nil
        }
    }

    func testRenderStopStill() async throws {
        let fixture = ProcessInfo.processInfo.environment["KAMOME_STOP_STILL"] ?? ""
        try XCTSkipUnless(
            !fixture.isEmpty,
            "Manual review harness — set KAMOME_STOP_STILL to a fixture name (e.g. iceland)."
        )
        let (trip, config) = try await RecapDemoFilmTests.importedRecap(named: fixture)
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config, establishing: establishing(trip)))

        // The stop worth reviewing is the one that exercises the whole
        // composition: the most photos, so the deck stacks and the dots page, and
        // among ties the *latest*, so the distance readout has something to say —
        // the first stop of a trip is 0 km in and shows neither trail nor figure.
        let stop = try XCTUnwrap(
            trip.stops.enumerated().filter { !$0.element.photos.isEmpty }
                .max { ($0.element.photos.count, $0.offset) < ($1.element.photos.count, $1.offset) }?.element,
            "the fixture has no stop with photos"
        )
        let peak = try XCTUnwrap(peakTime(timeline, stop: stop), "the stop's deck never opens")

        let style = RecapStyle.modernMinimal
        let compositor = FrameCompositor(
            timeline: timeline,
            subject: VehicleSubjectRenderer.make(style: style),
            overlay: RecapOverlayRenderer(style: style, resolver: try resolver(for: trip)),
            style: style,
            widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
        )
        let frame = timeline.cameraFrame(atTime: peak)
        let background = try await provider(for: trip).snapshot(
            frame, map: MapState(), widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
        )
        let image = try compositor.render(atTime: peak, background: RecapBackground(current: background))

        let outDir = outputDirectory()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("stop-\(fixture).png")
        try write(image, to: url)
        print("KAMOME_STOP_STILL \(url.path) — \(stop.name) · \(stop.photos.count) photos · t=\(peak)s")
    }

    // MARK: - Scene selection

    /// The instant this stop's deck is most open — the frame that shows the
    /// composition at full size rather than mid-bloom.
    private func peakTime(_ timeline: LinearTimeline, stop: RecapTrip.Stop, dt: Double = 1.0 / 30) -> Double? {
        var best: (time: Double, reveal: Double)?
        var time = 0.0
        while time <= timeline.durationS {
            for content in timeline.overlayContents(atTime: time) {
                guard case let .photoDeck(deck) = content,
                      deck.photos.first == stop.photos.first, deck.opacity > 0.99 else { continue }
                if deck.reveal > (best?.reveal ?? -1) { best = (time, deck.reveal) }
            }
            time += dt
        }
        return best?.time
    }

    private func establishing(_ trip: RecapTrip) -> RecapBounds? {
        guard let bounds = GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) }),
              let region = RecapMapRegionResolver.resolve(covering: bounds) else { return nil }
        return RecapBounds(
            minLat: region.bounds.minLat, minLon: region.bounds.minLon,
            maxLat: region.bounds.maxLat, maxLon: region.bounds.maxLon
        )
    }

    // MARK: - Providers and assets

    private func provider(for trip: RecapTrip) throws -> MapRenderer {
        #if canImport(MapLibre)
        guard let bounds = GeoBox.enclosing(trip.route.map { (lat: $0.lat, lon: $0.lon) }),
              let region = RecapMapRegionResolver.resolve(covering: bounds) else {
            XCTFail("no installed region covers the trip — set TEST_RUNNER_KAMOME_TILES_PATH")
            return MapKitSnapshotProvider()
        }
        return MapLibreSnapshotProvider(styleURL: try RecapMapStyle.resolvedStyleURL(
            styleResource: RecapMapTiles.styleResource, tilesURL: region.tilesURL, terrainURL: region.terrainURL
        ))
        #else
        return MapKitSnapshotProvider()
        #endif
    }

    /// Real photographs from `KAMOME_STOP_PHOTOS`, dealt across the trip's photo
    /// slots in filename order and cycled if the folder is shorter than the trip.
    private func resolver(for trip: RecapTrip) throws -> RecapPhotoResolving {
        let refs = trip.stops.flatMap(\.photos)
        let folder = ProcessInfo.processInfo.environment["KAMOME_STOP_PHOTOS"].map { URL(fileURLWithPath: $0) }
        let files = folder.flatMap {
            try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
                .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } ?? []
        if files.isEmpty { print("KAMOME_STOP_STILL no real photos — set KAMOME_STOP_PHOTOS for a truthful still") }

        var images: [String: CGImage] = [:]
        for (index, ref) in refs.enumerated() {
            guard case let .asset(id) = ref else { continue }
            let real = files.isEmpty ? nil : load(files[index % files.count])
            images[id] = try real ?? photoTile(index: index)
        }
        return FolderResolver(images: images)
    }

    private func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The fallback "photo": a flat gradient, so a still rendered without real
    /// images is obviously a layout check and not a look check.
    private func photoTile(index: Int) throws -> CGImage {
        let side = 900
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let hue = CGFloat(index % 5) / 5
        let gradient = try XCTUnwrap(CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 0.25 + hue * 0.5, green: 0.45, blue: 0.7 - hue * 0.4, alpha: 1),
            CGColor(srgbRed: 0.12 + hue * 0.25, green: 0.22, blue: 0.35 - hue * 0.2, alpha: 1)
        ] as CFArray, locations: [0, 1]))
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
        return try XCTUnwrap(context.makeImage())
    }

    private func outputDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["KAMOME_RENDER_OUT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("kamome-stop-still", isDirectory: true)
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "PNG write failed")
    }
}
