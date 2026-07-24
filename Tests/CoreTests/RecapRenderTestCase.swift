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
    let headRGB = RGB(red: 255, green: 74, blue: 69)
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
            centerLat: position.lat,
            centerLon: position.lon,
            spanM: config.cameraSpanM,
            bearing: 0,
            widthPx: config.frameWidthPx,
            heightPx: config.frameHeightPx
        )
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
final class CountingProvider: RecapSnapshotProviding {
    private let inner = FlatSnapshotProvider()
    private let lock = NSLock()
    private var count = 0

    var requestCount: Int {
        lock.withLock { count }
    }

    func snapshot(
        centerLat: Double, centerLon: Double, spanM: Double, bearing: Double, widthPx: Int, heightPx: Int
    ) async throws -> MapSnapshot {
        lock.withLock { count += 1 }
        return try await inner.snapshot(
            centerLat: centerLat, centerLon: centerLon, spanM: spanM, bearing: bearing,
            widthPx: widthPx, heightPx: heightPx
        )
    }
}
