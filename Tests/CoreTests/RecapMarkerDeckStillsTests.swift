import CoreGraphics
import CoreText
import Foundation
import ImageIO
import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import UniformTypeIdentifiers
import XCTest

/// Manual review harness for §4/§5 — **not** a CI test. It composites the
/// vehicle marker and the two-beat photo deck (`RecapTrip` → `LinearTimeline` →
/// `FrameCompositor`) over the deterministic `FlatSnapshotProvider` (no map SDK,
/// no Metal) and writes full-resolution PNG stills so Chiu can judge the
/// *layout* — car size, marker shapes, peak photo size, deck dots, and the stop
/// pin/label — before a device render. The follow-cam *feel* still needs the
/// MapLibre device render (§6); these stills only pin down proportions.
///
/// Run (simulator):
///   KAMOME_MARKER_STILLS=1 xcodebuild -scheme Kamome test \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///     -only-testing:KamomeCoreTests/RecapMarkerDeckStillsTests
/// The console prints the output directory; override it with KAMOME_RENDER_OUT.
final class RecapMarkerDeckStillsTests: XCTestCase {
    /// A `RecapPhotoResolving` over an in-memory id→bitmap map (the deck stills'
    /// stand-in "photos").
    private struct MapResolver: RecapPhotoResolving {
        let images: [String: CGImage]
        func image(for ref: PhotoRef, targetPx: Int) -> CGImage? {
            if case let .asset(id) = ref { return images[id] }
            return nil
        }
    }

    /// Bundled scene inputs so the render helpers stay small (lint body length).
    private struct Scene {
        let config: TrackingConfig.Export
        let timeline: LinearTimeline
        let resolver: RecapPhotoResolving
        let outDir: URL

        func compositor(marker: VehicleMarker) -> FrameCompositor {
            var style = RecapStyle()
            style.fallbackMarker = marker
            return FrameCompositor(
                timeline: timeline,
                subject: VehicleSubjectRenderer.make(style: style),
                overlay: RecapOverlayRenderer(style: style, resolver: resolver),
                widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
            )
        }

        func render(_ comp: FrameCompositor, at time: Double, on provider: FlatSnapshotProvider) async throws -> CGImage {
            let frame = timeline.cameraFrame(atTime: time)
            let background = try await provider.snapshot(
                CameraFrame(centerLat: frame.centerLat, centerLon: frame.centerLon, spanM: frame.spanM, bearing: frame.bearing),
                map: MapState(), widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
            )
            return try comp.render(atTime: time, background: RecapBackground(current: background))
        }
    }

    private let light = FlatSnapshotProvider(red: 0.93, green: 0.93, blue: 0.91)
    private let dark = FlatSnapshotProvider(red: 0.09, green: 0.11, blue: 0.16)

    private func stillsConfig() -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: 12, fps: 30, stopHoldS: 1.5, maxHoldFraction: 0.8,
            gifFps: 12, gifWidthPx: 480, frameWidthPx: 1080, frameHeightPx: 1920,
            cameraSpanM: 1500, wideSpanPadding: 1.15, zoomTransitionS: 0.8, actSplitKm: 25, followHeadingUp: false,
            cameraPanWindowFractionPerS: 0.35, cameraDeadZoneFraction: 0.7, cameraSafeZoneFraction: 0.8,
            cameraResponsiveness: 6.0, endRevealS: 2.5, endRevealPadding: 1.9, endCardStyle: "full",
            deckPhotoHoldS: 0.8, deckPhotoMinHoldS: 0.2, deckZoomS: 0.5, deckLabelLeadS: 0.6, subjectParkS: 0.4,
            openingCountryS: 1.0, openingRegionalS: 1.0, countryViewPadding: 2.2, firstStopDwellScale: 0.55,
            openingCollapseZoomRatio: 1.25, openingCollapseDriftFraction: 0.15,
            stopDwellMinS: 6, stopDwellMaxS: 25,
            totalDurationMinS: 60, totalDurationMaxS: 90,
            keyframeIntervalFrames: 15, titleCardS: 2.5, endCardS: 3, videoBitrateMbps: 5,
            stopWeightingEnabled: false, waypointMaxPhotos: 2, waypointMaxDwellS: 900, waypointHoldS: 0.8,
            uncappedPhotoHoldS: 1.0,
            allocationZeroShare: 0.4, allocationOneShare: 0.3,
            allocationTwoShare: 0.2, allocationMaxPhotos: 3, favoriteWeight: 3.0,
            tierTopShare: 0.15,
            tierStandardPhotos: 3, tierTopPhotos: 5,
            earnedStopsFloor: 8, earnedStopsCap: 21,
            earnedStopsPerDoubling: 7, earnedStopsReferenceTripStops: 10,
            recapMode: .highlight
        )
    }

    /// A gentle north-east route so the marker sits at an angle (representative
    /// of driving), with the stop mid-way.
    private let route: [RecapCoordinate] = (0...20).map {
        RecapCoordinate(lat: -32.0 + Double($0) * 0.002, lon: 115.75 + Double($0) * 0.0016)
    }

    func testRenderMarkerAndDeckStills() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_MARKER_STILLS"] == "1",
            "Manual review harness — set KAMOME_MARKER_STILLS=1 to render marker + deck stills."
        )
        let config = stillsConfig()
        let deck = RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS,
            labelLeadS: config.deckLabelLeadS, photoMinHoldS: config.deckPhotoMinHoldS
        )
        let photos = try (0..<4).map { try photoTile(index: $0) }
        let refs = (0..<photos.count).map { PhotoRef.asset("p\($0)") }
        let images = Dictionary(uniqueKeysWithValues: zip((0..<photos.count).map { "p\($0)" }, photos))
        let stop = RecapTrip.Stop(
            coordinate: route[10], name: "小樽運河", dayLabel: "Day 3", detail: nil,
            photos: refs, dwellS: deck.dwellS(photoCount: photos.count)
        )
        let trip = RecapTrip(
            route: route, stops: [stop], title: "小樽", subtitle: "Day 3",
            statsLines: ["120 km · 1 stop"], callToAction: "Get this route", shareURL: "kamome://route/stills"
        )
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config, pacing: .fixed(totalS: config.targetDurationS)))
        let outDir = outputDirectory()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let scene = Scene(config: config, timeline: timeline, resolver: MapResolver(images: images), outDir: outDir)
        let deckTimes = deckActiveTimes(timeline)
        try await renderMarkerSet(scene, at: (deckTimes.first ?? 4) * 0.5)
        try await renderDeckEnvelope(scene, deckTimes: deckTimes)
        print("KAMOME MARKER+DECK STILLS → \(outDir.path)")
    }

    // MARK: - Render passes

    /// The swappable marker set at a travel moment, on both backgrounds.
    private func renderMarkerSet(_ scene: Scene, at time: Double) async throws {
        for marker in VehicleMarker.allCases {
            let comp = scene.compositor(marker: marker)
            let base = "marker-\(marker.rawValue)"
            try writePNG(try await scene.render(comp, at: time, on: light), to: scene.outDir, name: "\(base)-light")
            try writePNG(try await scene.render(comp, at: time, on: dark), to: scene.outDir, name: "\(base)-dark")
        }
    }

    /// The car deck through its envelope: grow → peak → shrink.
    private func renderDeckEnvelope(_ scene: Scene, deckTimes: [Double]) async throws {
        let car = scene.compositor(marker: .seagull)
        guard let grow = deckTimes.first, let shrink = deckTimes.last else { return }
        let mid = deckTimes[deckTimes.count / 2]
        try writePNG(try await scene.render(car, at: grow, on: light), to: scene.outDir, name: "deck-grow-light")
        try writePNG(try await scene.render(car, at: mid, on: light), to: scene.outDir, name: "deck-peak-light")
        try writePNG(try await scene.render(car, at: mid, on: dark), to: scene.outDir, name: "deck-peak-dark")
        try writePNG(try await scene.render(car, at: shrink, on: light), to: scene.outDir, name: "deck-shrink-light")
    }

    /// Instants where the stop's photo deck is active, so the envelope passes
    /// can pick grow / peak / shrink without recomputing the window.
    private func deckActiveTimes(_ timeline: LinearTimeline, dt: Double = 1.0 / 30) -> [Double] {
        var times: [Double] = []
        var time = 0.0
        while time <= timeline.durationS {
            let hasDeck = timeline.overlayContents(atTime: time).contains {
                if case .photoDeck = $0 { return true }
                return false
            }
            if hasDeck { times.append(time) }
            time += dt
        }
        return times
    }

    // MARK: - Helpers

    private func outputDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["KAMOME_RENDER_OUT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("kamome-marker-deck-stills", isDirectory: true)
    }

    /// A stand-in "photo": a diagonal gradient with a big index, so the deck's
    /// framing and rotation read clearly in the still.
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
             CGColor(srgbRed: 0.18, green: 0.30, blue: 0.20, alpha: 1)),
            (CGColor(srgbRed: 0.55, green: 0.35, blue: 0.55, alpha: 1),
             CGColor(srgbRed: 0.28, green: 0.18, blue: 0.28, alpha: 1))
        ]
        let (top, bottom) = palettes[index % palettes.count]
        let gradient = try XCTUnwrap(CGGradient(
            colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1]
        ))
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])

        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 320, nil)
        let textColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85)
        let attrs = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: textColor] as CFDictionary
        let attributed = CFAttributedStringCreate(kCFAllocatorDefault, "\(index + 1)" as CFString, attrs)
        let line = CTLineCreateWithAttributedString(attributed!)
        let bounds = CTLineGetImageBounds(line, context)
        context.textPosition = CGPoint(x: (CGFloat(side) - bounds.width) / 2, y: (CGFloat(side) - bounds.height) / 2)
        CTLineDraw(line, context)
        return try XCTUnwrap(context.makeImage())
    }

    private func writePNG(_ image: CGImage, to dir: URL, name: String) throws {
        let url = dir.appendingPathComponent("\(name).png")
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "PNG write failed for \(name)")
    }
}
