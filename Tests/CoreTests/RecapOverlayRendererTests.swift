import CoreGraphics
import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
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
        let recorded = RecapRouteLeg(coordinates: coords, mode: .drive, provenance: .recorded)
        let frame = try await render(
            [.routeReveal([recorded])], resolverImage: try makeSolidImage(red: 0, green: 1, blue: 0)
        )
        XCTAssertGreaterThan(try colorCount(frame, matching: routeRGB), 0, "the trail must stroke in the route color")
    }

    // MARK: - Honest provenance in the film itself (PD-1)

    /// A long north-south leg down the frame's center, so a dash pattern shows
    /// up as gaps along a column of pixels.
    private func meridianLeg(_ provenance: RouteProvenance) -> RecapRouteLeg {
        RecapRouteLeg(
            coordinates: (0...40).map { RecapCoordinate(lat: -32.0 + Double($0 - 20) * 0.0004, lon: 115.75) },
            mode: .drive,
            provenance: provenance
        )
    }

    /// The load-bearing honesty test: a leg Kamome could not reconstruct must be
    /// visibly a guess **in the exported film**, because the film is the public
    /// artifact. Solid vs. dashed is the whole point — a viewer must not read an
    /// inferred straight line as a road we watched.
    func testInferredLegIsDashedWhileConfidentLegIsSolid() async throws {
        let green = try makeSolidImage(red: 0, green: 1, blue: 0)
        let solid = try await render([.routeReveal([meridianLeg(.recorded)])], resolverImage: green)
        let dashed = try await render([.routeReveal([meridianLeg(.inferred)])], resolverImage: green)

        let solidRun = try longestPaintedRun(solid, col: widthPx / 2)
        let dashedRun = try longestPaintedRun(dashed, col: widthPx / 2)
        XCTAssertGreaterThan(solidRun, 0, "the confident leg must draw")
        XCTAssertGreaterThan(dashedRun, 0, "the inferred leg must still draw — it happened, we just don't know how")
        XCTAssertLessThan(dashedRun, solidRun / 2, "an inferred leg is broken by gaps, not one continuous stroke")
    }

    /// A reconstructed leg is road, even though nobody watched the traveling —
    /// it gets the confident stroke, same as recorded.
    func testReconstructedLegDrawsSolidLikeRecorded() async throws {
        let green = try makeSolidImage(red: 0, green: 1, blue: 0)
        let recorded = try await render([.routeReveal([meridianLeg(.recorded)])], resolverImage: green)
        let reconstructed = try await render([.routeReveal([meridianLeg(.reconstructed)])], resolverImage: green)
        XCTAssertEqual(
            try longestPaintedRun(reconstructed, col: widthPx / 2),
            try longestPaintedRun(recorded, col: widthPx / 2),
            "snapped-to-road geometry is a confident claim"
        )
    }

    /// Mixed provenance in one reveal: both strokes appear, each in its own key.
    func testMixedLegsDrawEachInItsOwnTreatment() async throws {
        let green = try makeSolidImage(red: 0, green: 1, blue: 0)
        let confident = RecapRouteLeg(
            coordinates: (0...20).map { RecapCoordinate(lat: -32.004 + Double($0) * 0.0002, lon: 115.75) },
            mode: .drive, provenance: .reconstructed
        )
        let guessed = RecapRouteLeg(
            coordinates: (0...20).map { RecapCoordinate(lat: -32.0 + Double($0) * 0.0002, lon: 115.75) },
            mode: .walk, provenance: .inferred
        )
        let frame = try await render([.routeReveal([confident, guessed])], resolverImage: green)

        // The confident half runs unbroken; the inferred half is chopped up.
        let confidentRun = try longestPaintedRun(frame, col: widthPx / 2, rows: (heightPx / 2)..<heightPx)
        let guessedRun = try longestPaintedRun(frame, col: widthPx / 2, rows: 0..<(heightPx / 2))
        XCTAssertGreaterThan(confidentRun, 0)
        XCTAssertGreaterThan(guessedRun, 0)
        XCTAssertLessThan(guessedRun, confidentRun, "the two legs must not read the same")
    }

    /// The longest unbroken run of non-background pixels down one column — how a
    /// dash pattern is told from a solid stroke without golden bitmaps.
    private func longestPaintedRun(
        _ image: CGImage, col: Int, rows: Range<Int>? = nil
    ) throws -> Int {
        var longest = 0
        var run = 0
        for row in rows ?? 0..<heightPx {
            let sample = try pixel(image, col: col, row: row)
            if sample != backgroundRGB {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }
        return longest
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
        // The card was sized up for photo recall (Chiu 2026-07-30); it must still
        // leave the map and trail visible around its edges.
        XCTAssertLessThan(Double(openArea) / Double(widthPx * heightPx), 0.5, "the map stays visible around the card")

        // At zero opacity the deck is absent.
        let none = try await render([deck(reveal: 1, opacity: 0)], resolverImage: green)
        XCTAssertEqual(try colorCount(none, matching: greenRGB), 0, "no deck at zero opacity")
    }

    /// Beat 1: the pin marks the stop **on the stop's own point**, and the stop's
    /// name stands on it (Chiu 2026-07-26). The pin used to be pushed clear of
    /// the parked car by a pixel-sized clearance, which at a wide framing put it
    /// kilometres from the place it was labelling; the car now parks and vanishes
    /// for the stop, so the pin belongs on the spot.
    ///
    /// The name is unplated type (the 2026-07-31 prototype port dropped the pill),
    /// so the probe hunts the glyph fill itself rather than a panel behind it.
    func testStopLabelPinsTheStopItselfWithTheNameStandingOnIt() async throws {
        // Distinctive ink so the name's own pixels are findable over the map.
        var style = opaqueCardStyle
        let nameRGB = RGB(red: 255, green: 0, blue: 255)
        style.labelTextColor = CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        let label = OverlayContent.stopLabel(
            name: "小樽運河", coordinate: RecapCoordinate(lat: -32.0, lon: 115.75), detail: nil,
            dayLabel: "Day 1", travelledM: 0, opacity: 1
        )
        let frame = try await render(
            [label], resolverImage: try makeSolidImage(red: 0, green: 1, blue: 0), style: style
        )

        // The stop projects to the frame center.
        let stopRow = heightPx / 2
        let scale = Double(widthPx) / 1080
        let pinRadiusRows = Int(Double(style.labelPinRadiusPx) * 1.5 * scale)

        // Rows count downward, so an element's bottom edge is its largest row.
        let pinRGB = RGB(red: 89, green: 217, blue: 242)  // labelPinColor
        let pinBottomRow = try XCTUnwrap(lastRow(of: frame, matching: pinRGB), "the pin must draw")
        let nameBottomRow = try XCTUnwrap(lastRow(of: frame, matching: nameRGB), "the stop's name must draw")

        // The pin is centred on the stop itself — its bottom edge sits one pin
        // radius below the stop's row, not a car's length away from it.
        XCTAssertEqual(
            pinBottomRow, stopRow + pinRadiusRows, accuracy: 2,
            "the pin must be drawn on the stop, not offset from it"
        )
        XCTAssertLessThan(nameBottomRow, pinBottomRow, "the name stands on the pin")
    }

    /// The largest row containing `target` — an element's bottom edge. Matched
    /// with a tolerance because antialiased type never lands on an exact tone.
    private func lastRow(of frame: CGImage, matching target: RGB, tolerance: Int = 12) throws -> Int? {
        var found: Int?
        for row in 0..<heightPx {
            for col in 0..<widthPx {
                let sample = try pixel(frame, col: col, row: row)
                if abs(sample.red - target.red) <= tolerance,
                   abs(sample.green - target.green) <= tolerance,
                   abs(sample.blue - target.blue) <= tolerance {
                    found = row
                    break
                }
            }
        }
        return found
    }

    // MARK: - The stop's typography layer (2026-07-31 prototype port)

    private func deckContent(photos: [PhotoRef], focusIndex: Int = 0, travelledM: Double = 0) -> OverlayContent {
        .photoDeck(RecapPhotoDeck(
            photos: photos, focusIndex: focusIndex, reveal: 1, opacity: 1,
            name: "小樽運河", dayLabel: "Day 3", travelledM: travelledM,
            coordinate: RecapCoordinate(lat: -32.0, lon: 115.75)
        ))
    }

    /// The dots say "which of this stop's photos you are looking at". A stop with
    /// one photo has nothing to page through, so it must show none — an indicator
    /// with a single dot reads as a broken control.
    func testProgressDotsAppearOnlyWhenAStopHasPhotosToPageThrough() async throws {
        var style = opaqueCardStyle
        let dotRGB = RGB(red: 255, green: 0, blue: 255)
        style.deckDotOnColor = CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        style.deckDotOffColor = CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        let green = try makeSolidImage(red: 0, green: 1, blue: 0)
        let refs = (0..<4).map { PhotoRef.asset("p\($0)") }

        let many = try await render([deckContent(photos: refs)], resolverImage: green, style: style)
        XCTAssertGreaterThan(try colorCount(many, matching: dotRGB), 0, "a four-photo stop pages, so it shows dots")
        let one = try await render([deckContent(photos: [refs[0]])], resolverImage: green, style: style)
        XCTAssertEqual(try colorCount(one, matching: dotRGB), 0, "a one-photo stop has nothing to page through")
    }

    /// The metadata pill belongs to the **photograph** — it rides on the card, so
    /// the lead-in beat (pin + name, no card yet) must not draw it.
    func testMetadataPillRidesOnThePhotoAndNotOnTheLeadInLabel() async throws {
        var style = opaqueCardStyle
        let pillRGB = RGB(red: 255, green: 0, blue: 255)
        style.deckMetaFillColor = CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        let green = try makeSolidImage(red: 0, green: 1, blue: 0)

        let deck = try await render(
            [deckContent(photos: [.asset("a"), .asset("b")], travelledM: 114_000)],
            resolverImage: green, style: style
        )
        XCTAssertGreaterThan(try colorCount(deck, matching: pillRGB), 0, "the deck beat carries the metadata pill")

        let lead = OverlayContent.stopLabel(
            name: "小樽運河", coordinate: RecapCoordinate(lat: -32.0, lon: 115.75), detail: nil,
            dayLabel: "Day 3", travelledM: 114_000, opacity: 1
        )
        let label = try await render([lead], resolverImage: green, style: style)
        XCTAssertEqual(try colorCount(label, matching: pillRGB), 0, "the lead-in beat has no photo to pin it to")
    }

    func testOverlayRenderingIsDeterministic() async throws {
        let green = try makeSolidImage(red: 0, green: 1, blue: 0)
        let contents: [OverlayContent] = [
            .routeReveal([RecapRouteLeg(
                coordinates: [RecapCoordinate(lat: -32.001, lon: 115.75), RecapCoordinate(lat: -32.0, lon: 115.75)],
                mode: .drive, provenance: .recorded
            )]),
            .stopLabel(
                name: "Stop", coordinate: RecapCoordinate(lat: -32.0, lon: 115.75),
                detail: "步行 21 分鐘", dayLabel: "Day 1", travelledM: 0, opacity: 0.5
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
