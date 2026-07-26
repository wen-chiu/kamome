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

    private func render(
        _ contents: [OverlayContent], resolverImage: CGImage, style: RecapStyle? = nil
    ) async throws -> CGImage {
        let config = exportConfig()
        let camera = CameraFrame(centerLat: -32.0, centerLon: 115.75, spanM: config.cameraSpanM, bearing: 0)
        let snapshot = try await FlatSnapshotProvider().snapshot(
            camera, map: MapState(), widthPx: widthPx, heightPx: heightPx
        )
        let context = try makeContext()
        let surface = RenderSurface(
            context: context, widthPx: widthPx, heightPx: heightPx, scale: CGFloat(widthPx) / 1080
        ) { lat, lon in snapshot.point(lat: lat, lon: lon) }
        let renderer = RecapOverlayRenderer(
            style: style ?? opaqueCardStyle, resolver: StubResolver(image: resolverImage)
        )
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

    func testPhotoDeckDrawsTheFocusPhotoAndGrowsWithReveal() async throws {
        let green = try makeSolidImage(red: 0, green: 1, blue: 0)
        let greenRGB = RGB(red: 0, green: 255, blue: 0)
        func deck(reveal: Double, opacity: Double) -> OverlayContent {
            .photoDeck(RecapPhotoDeck(
                photos: [.asset("a"), .asset("b")], focusIndex: 1,
                reveal: reveal, opacity: opacity, name: "小樽運河",
                coordinate: RecapCoordinate(lat: -32.0, lon: 115.75)
            ))
        }

        let open = try await render([deck(reveal: 1, opacity: 1)], resolverImage: green)
        XCTAssertGreaterThan(
            try colorCount(open, matching: greenRGB), 200, "resolved hero photo fills the card"
        )

        // The reveal drives on-screen size: fully open covers more than the
        // opening size, and both leave the map visible around the card.
        let opening = try await render([deck(reveal: 0, opacity: 1)], resolverImage: green)
        let openArea = try colorCount(open, matching: greenRGB)
        let openingArea = try colorCount(opening, matching: greenRGB)
        XCTAssertGreaterThan(openArea, Int(Double(openingArea) * 1.3), "the card grows with reveal")
        XCTAssertLessThan(Double(openArea) / Double(widthPx * heightPx), 0.35, "the map stays visible around the card")

        // At zero opacity the deck is absent.
        let none = try await render([deck(reveal: 1, opacity: 0)], resolverImage: green)
        XCTAssertEqual(try colorCount(none, matching: greenRGB), 0, "no deck at zero opacity")
    }

    /// Beat 1: the pin marks the stop on the map, and the name pill floats clear
    /// above where the vehicle sits — they must never overlap (Chiu 2026-07-25).
    func testStopLabelPinsTheStopAndFloatsTheNameClearOfTheVehicle() async throws {
        // An opaque pill so its fill is an exact color to hunt for.
        var style = opaqueCardStyle
        let pillRGB = RGB(red: 26, green: 31, blue: 41)
        style.labelPillColor = CGColor(srgbRed: 26 / 255, green: 31 / 255, blue: 41 / 255, alpha: 1)
        let label = OverlayContent.stopLabel(
            name: "小樽運河", coordinate: RecapCoordinate(lat: -32.0, lon: 115.75), detail: nil, opacity: 1
        )
        let frame = try await render(
            [label], resolverImage: try makeSolidImage(red: 0, green: 1, blue: 0), style: style
        )

        // The stop projects to the frame center — where the parked car sits.
        let stopRow = heightPx / 2
        let scale = Double(widthPx) / 1080
        let clearedRows = Int((Double(style.subjectLengthPx) / 2 + Double(style.labelVehicleClearancePx)) * scale)

        // Rows count downward, so each element's bottom edge is its largest row.
        let pinRGB = RGB(red: 89, green: 217, blue: 242)  // labelPinColor
        let pinBottomRow = try XCTUnwrap(
            lastRow(of: frame, matching: pinRGB), "the pin must draw"
        )
        let pillBottomRow = try XCTUnwrap(
            lastRow(of: frame, matching: pillRGB), "the name pill must draw"
        )

        // Both float clear of the car: neither may reach into its footprint.
        XCTAssertLessThanOrEqual(
            pinBottomRow, stopRow - clearedRows,
            "the pin must clear the vehicle's half-length + clearance"
        )
        XCTAssertLessThan(pillBottomRow, pinBottomRow, "the name sits above the pin in the floating group")
    }

    /// The largest row containing `target` — an element's bottom edge.
    private func lastRow(of frame: CGImage, matching target: RGB) throws -> Int? {
        var found: Int?
        for row in 0..<heightPx {
            for col in 0..<widthPx where try pixel(frame, col: col, row: row) == target {
                found = row
                break
            }
        }
        return found
    }

    func testOverlayRenderingIsDeterministic() async throws {
        let green = try makeSolidImage(red: 0, green: 1, blue: 0)
        let contents: [OverlayContent] = [
            .routeReveal([RecapCoordinate(lat: -32.001, lon: 115.75), RecapCoordinate(lat: -32.0, lon: 115.75)]),
            .stopLabel(
                name: "Stop", coordinate: RecapCoordinate(lat: -32.0, lon: 115.75),
                detail: "步行 21 分鐘", opacity: 0.5
            ),
            .photoDeck(RecapPhotoDeck(
                photos: [.asset("a"), .asset("b")], focusIndex: 0,
                reveal: 0.7, opacity: 0.7, name: "Stop", detail: "步行 21 分鐘",
                coordinate: RecapCoordinate(lat: -32.0, lon: 115.75)
            ))
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
