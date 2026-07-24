import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import XCTest

/// Layer-3 overlay renderer: deterministic drawing of each `OverlayContent` over
/// a flat snapshot. Pins down the route stroke, the deck bloom, and the stop
/// label without any map SDK (golden-frame-style).
final class RecapOverlayRendererTests: RecapRenderTestCase {
    private struct StubResolver: RecapPhotoResolving {
        let image: CGImage
        func image(for ref: PhotoRef, targetPx: Int) -> CGImage? { image }
    }

    private func makeContext() throws -> CGContext {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: widthPx, height: heightPx, bitsPerComponent: 8, bytesPerRow: 0,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.91, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: widthPx, height: heightPx))
        return context
    }

    private func render(_ contents: [OverlayContent], resolverImage: CGImage) async throws -> CGImage {
        let config = exportConfig()
        let camera = CameraFrame(centerLat: -32.0, centerLon: 115.75, spanM: config.cameraSpanM, bearing: 0)
        let snapshot = try await FlatSnapshotProvider().snapshot(
            camera, map: MapState(), widthPx: widthPx, heightPx: heightPx
        )
        let context = try makeContext()
        let surface = RenderSurface(
            context: context, widthPx: widthPx, heightPx: heightPx, scale: CGFloat(widthPx) / 1080
        ) { lat, lon in snapshot.point(lat: lat, lon: lon) }
        let renderer = RecapOverlayRenderer(style: opaqueCardStyle, resolver: StubResolver(image: resolverImage))
        for content in contents {
            renderer.render(content, camera: camera, into: surface)
        }
        return try XCTUnwrap(context.makeImage())
    }

    func testRouteRevealStrokesTheTrail() async throws {
        let coords = (0...10).map { RecapCoordinate(lat: -32.0 + Double($0 - 5) * 0.001, lon: 115.75) }
        let frame = try await render([.routeReveal(coords)], resolverImage: try makeSolidImage(red: 0, green: 1, blue: 0))
        XCTAssertGreaterThan(try colorCount(frame, matching: routeRGB), 0, "the trail must stroke in the route color")
    }

    func testPhotoDeckBloomsTheFocusPhotoAtPeak() async throws {
        let green = try makeSolidImage(red: 0, green: 1, blue: 0)
        let deck = RecapPhotoDeck(photos: [.asset("a"), .asset("b")], focusIndex: 1, emphasis: 1)
        let frame = try await render([.photoDeck(deck)], resolverImage: green)
        let row = Int(Double(heightPx) * 0.45)  // the deck card sits a touch above center
        try assertPixel(frame, col: widthPx / 2, row: row, is: RGB(red: 0, green: 255, blue: 0), "resolved hero photo at peak")

        // At emphasis 0 the deck is absent.
        let none = try await render(
            [.photoDeck(RecapPhotoDeck(photos: [.asset("a")], focusIndex: 0, emphasis: 0))], resolverImage: green
        )
        try assertPixel(none, col: widthPx / 2, row: row, is: backgroundRGB, "no deck at zero emphasis")
    }

    func testStopLabelDrawsAPinAtTheCoordinate() async throws {
        // The label's pin sits at the projected coordinate = frame center here.
        let label = OverlayContent.stopLabel(name: "小樽運河", coordinate: RecapCoordinate(lat: -32.0, lon: 115.75), detail: nil)
        let frame = try await render([label], resolverImage: try makeSolidImage(red: 0, green: 1, blue: 0))
        let pin = try pixel(frame, col: widthPx / 2, row: heightPx / 2)
        XCTAssertNotEqual(pin, backgroundRGB, "the pin must draw at the stop coordinate")
    }

    func testOverlayRenderingIsDeterministic() async throws {
        let green = try makeSolidImage(red: 0, green: 1, blue: 0)
        let contents: [OverlayContent] = [
            .routeReveal([RecapCoordinate(lat: -32.001, lon: 115.75), RecapCoordinate(lat: -32.0, lon: 115.75)]),
            .stopLabel(name: "Stop", coordinate: RecapCoordinate(lat: -32.0, lon: 115.75), detail: "步行 21 分鐘"),
            .photoDeck(RecapPhotoDeck(photos: [.asset("a"), .asset("b")], focusIndex: 0, emphasis: 0.7))
        ]
        let first = try await render(contents, resolverImage: green)
        let second = try await render(contents, resolverImage: green)
        XCTAssertEqual(
            try XCTUnwrap(pixels(first).data as Data?),
            try XCTUnwrap(pixels(second).data as Data?),
            "identical content must render byte-identically"
        )
    }
}
