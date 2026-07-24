import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import XCTest

/// Shared harness for the §4.5 golden-frame gates: a 1 km straight meridian
/// route rendered into a small 216×384 frame (1080×1920 ÷ 5), the flat
/// provider for determinism, and pixel probes for composition assertions.
/// Subclasses hold the actual tests (RecapFrameTests, RecapChromeTests).
class RecapRenderTestCase: XCTestCase {
    struct RGB: Equatable {
        let red: Int
        let green: Int
        let blue: Int
    }

    let route: [CameraPath.Point] = (0...10).map {
        CameraPath.Point(lat: -32.0 + Double($0) * 0.0009, lon: 115.75)
    }

    let widthPx = 216
    let heightPx = 384

    // Style colors as 8-bit sRGB, for pixel assertions.
    let routeRGB = RGB(red: 33, green: 115, blue: 242)
    // Vehicle marker body (RecapStyle.markerColor) — the car fills its center.
    let markerRGB = RGB(red: 255, green: 74, blue: 69)
    let backgroundRGB = RGB(red: 237, green: 237, blue: 232)
    let cardRGB = RGB(red: 255, green: 255, blue: 255)

    func exportConfig(
        targetDurationS: Double = 6,
        fps: Int = 10,
        keyframeIntervalFrames: Int = 15
    ) -> TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: targetDurationS, fps: fps, stopHoldS: 1.5, maxHoldFraction: 0.5,
            gifFps: 12, gifWidthPx: 480, frameWidthPx: widthPx, frameHeightPx: heightPx,
            cameraSpanM: 1500, wideSpanPadding: 1.15, zoomTransitionS: 0.8, followHeadingUp: false,
            deckPhotoHoldS: 0.8, deckZoomS: 0.5, deckSpanM: 600, deckLabelLeadS: 0.6,
            keyframeIntervalFrames: keyframeIntervalFrames,
            titleCardS: 1, endCardS: 1, videoBitrateMbps: 5
        )
    }

    /// Card at full opacity so its pixels are exactly white regardless of the
    /// background under it.
    var opaqueCardStyle: RecapStyle {
        var style = RecapStyle()
        style.cardColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        return style
    }

    func makePipeline(
        stops: [CameraPath.Point] = [],
        photosEnabled: Bool = true,
        stopCards: [RecapFrameCompositor.StopCard] = [],
        titleCard: RecapFrameCompositor.TitleCard? = nil,
        endCard: RecapFrameCompositor.EndCard? = nil,
        config: TrackingConfig.Export
    ) throws -> (path: CameraPath, compositor: RecapFrameCompositor) {
        let path = try XCTUnwrap(CameraPath(route: route, stops: stops, config: config))
        let events = OverlayTimeline.build(holds: path.holds, config: config, photosEnabled: photosEnabled)
        let compositor = RecapFrameCompositor(
            path: path,
            events: events,
            stopCards: stopCards,
            titleCard: titleCard,
            endCard: endCard,
            widthPx: config.frameWidthPx,
            heightPx: config.frameHeightPx,
            style: opaqueCardStyle
        )
        return (path, compositor)
    }

    func snapshot(centeredAt position: CameraPath.Position, config: TrackingConfig.Export) async throws -> MapSnapshot {
        try await FlatSnapshotProvider().snapshot(
            CameraFrame(centerLat: position.lat, centerLon: position.lon, spanM: config.cameraSpanM, bearing: 0),
            map: MapState(), widthPx: config.frameWidthPx, heightPx: config.frameHeightPx
        )
    }

    /// A solid-color test photo for deck rendering — distinct fills let a pixel
    /// probe tell which photo the deck is showing.
    func makeSolidImage(red: CGFloat, green: CGFloat, blue: CGFloat, side: Int = 16) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return try XCTUnwrap(context.makeImage())
    }

    // MARK: - Pixel probes

    func pixels(_ image: CGImage) throws -> (data: CFData, bytesPerRow: Int) {
        let data = try XCTUnwrap(image.dataProvider?.data)
        return (data, image.bytesPerRow)
    }

    func pixel(_ image: CGImage, col: Int, row: Int) throws -> RGB {
        let (data, bytesPerRow) = try pixels(image)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        let offset = row * bytesPerRow + col * 4
        return RGB(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
    }

    func assertPixel(
        _ image: CGImage,
        col: Int,
        row: Int,
        is expected: RGB,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actual = try pixel(image, col: col, row: row)
        for (component, want) in [(actual.red, expected.red), (actual.green, expected.green), (actual.blue, expected.blue)] {
            XCTAssertEqual(
                component, want, accuracy: 3,
                "\(label) at (\(col),\(row)): got \(actual), expected \(expected)", file: file, line: line
            )
        }
    }

    func colorCount(_ image: CGImage, matching target: RGB) throws -> Int {
        let (data, bytesPerRow) = try pixels(image)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        var count = 0
        for row in 0..<image.height {
            for col in 0..<image.width {
                let offset = row * bytesPerRow + col * 4
                if abs(Int(bytes[offset]) - target.red) <= 3,
                   abs(Int(bytes[offset + 1]) - target.green) <= 3,
                   abs(Int(bytes[offset + 2]) - target.blue) <= 3 {
                    count += 1
                }
            }
        }
        return count
    }
}

/// Counts provider hits so the keyframe cache is provably doing its job.
/// Lock-guarded: the render loop prefetches snapshots concurrently.
final class CountingProvider: MapRenderer {
    private let inner = FlatSnapshotProvider()
    private let lock = NSLock()
    private var count = 0

    var capabilities: MapRendererCapabilities { inner.capabilities }

    var requestCount: Int {
        lock.withLock { count }
    }

    func snapshot(_ frame: CameraFrame, map: MapState, widthPx: Int, heightPx: Int) async throws -> MapSnapshot {
        lock.withLock { count += 1 }
        return try await inner.snapshot(frame, map: map, widthPx: widthPx, heightPx: heightPx)
    }
}
