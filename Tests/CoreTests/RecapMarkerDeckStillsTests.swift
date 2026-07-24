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
/// vehicle marker and the photo deck over the deterministic `FlatSnapshotProvider`
/// (no map SDK, no Metal) and writes full-resolution PNG stills so Chiu can
/// judge the *layout* — car size, marker shapes, peak photo size, deck caption
/// and dots — before a device render. The follow-cam *feel* still needs the
/// MapLibre device render (§6); these stills only pin down proportions.
///
/// Run (simulator):
///   KAMOME_MARKER_STILLS=1 xcodebuild -scheme Kamome test \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///     -only-testing:KamomeCoreTests/RecapMarkerDeckStillsTests
/// The console prints the output directory; override it with KAMOME_RENDER_OUT.
final class RecapMarkerDeckStillsTests: XCTestCase {
    /// Bundled scene inputs so the render helpers stay small (lint body length).
    private struct Scene {
        let config: TrackingConfig.Export
        let path: CameraPath
        let events: [OverlayEvent]
        let card: RecapFrameCompositor.StopCard
        let deck: RecapDeck
        let outDir: URL

        func compositor(marker: VehicleMarker) -> RecapFrameCompositor {
            var style = RecapStyle()
            style.vehicleMarker = marker
            return RecapFrameCompositor(
                path: path, events: events, stopCards: [card],
                widthPx: config.frameWidthPx, heightPx: config.frameHeightPx, style: style, deck: deck
            )
        }

        func render(_ comp: RecapFrameCompositor, at time: Double, on provider: FlatSnapshotProvider) async throws -> CGImage {
            let position = path.position(atTime: time)
            let background = try await provider.snapshot(
                CameraFrame(centerLat: position.lat, centerLon: position.lon, spanM: config.cameraSpanM, bearing: 0),
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
            cameraSpanM: 1500, wideSpanPadding: 1.15, zoomTransitionS: 0.8, followHeadingUp: false,
            deckPhotoHoldS: 0.8, deckZoomS: 0.5, deckSpanM: 600, deckLabelLeadS: 0.6,
            keyframeIntervalFrames: 15, titleCardS: 2.5, endCardS: 3, videoBitrateMbps: 5
        )
    }

    /// A gentle north-east route so the marker sits at an angle (representative
    /// of driving), with the stop mid-way.
    private let route: [CameraPath.Point] = (0...20).map {
        CameraPath.Point(lat: -32.0 + Double($0) * 0.002, lon: 115.75 + Double($0) * 0.0016)
    }

    func testRenderMarkerAndDeckStills() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["KAMOME_MARKER_STILLS"] == "1",
            "Manual review harness — set KAMOME_MARKER_STILLS=1 to render marker + deck stills."
        )
        let config = stillsConfig()
        let deck = RecapDeck(photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS, labelLeadS: config.deckLabelLeadS)
        let photos = try (0..<4).map { try photoTile(index: $0) }
        let path = try XCTUnwrap(CameraPath(
            route: route, stops: [route[10]], config: config,
            stopHoldsS: [deck.dwellS(photoCount: photos.count)]
        ))
        let hold = try XCTUnwrap(path.holds.first)
        let card = RecapFrameCompositor.StopCard(name: "小樽運河", dayLabel: "Day 3", detail: nil, photos: photos)
        let events = OverlayTimeline.build(holds: path.holds, config: config, photosEnabled: true)
        let outDir = outputDirectory()
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let scene = Scene(config: config, path: path, events: events, card: card, deck: deck, outDir: outDir)
        try await renderMarkerSet(scene, at: hold.startS * 0.5)
        try await renderDeckEnvelope(scene, hold: hold)
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
    private func renderDeckEnvelope(_ scene: Scene, hold: CameraPath.Hold) async throws {
        let car = scene.compositor(marker: .car)
        let mid = (hold.startS + hold.endS) / 2
        try writePNG(try await scene.render(car, at: hold.startS + 0.2, on: light), to: scene.outDir, name: "deck-grow-light")
        try writePNG(try await scene.render(car, at: mid, on: light), to: scene.outDir, name: "deck-peak-light")
        try writePNG(try await scene.render(car, at: mid, on: dark), to: scene.outDir, name: "deck-peak-dark")
        try writePNG(try await scene.render(car, at: hold.endS - 0.2, on: light), to: scene.outDir, name: "deck-shrink-light")
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
