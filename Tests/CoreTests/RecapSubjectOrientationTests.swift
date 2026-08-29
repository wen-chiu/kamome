import CoreGraphics
import Foundation
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// The subject-orientation contract after the north-up reversal (Chiu
/// 2026-07-25): the **map never turns** — a rotating map hides the route's real
/// shape and the distance covered, which is what a travel recap exists to show —
/// so the *vehicle* carries the heading. The car is an 8-direction sprite set and
/// the renderer picks the nearest bucket; nothing is rotated at runtime.
final class RecapSubjectOrientationTests: RecapRenderTestCase {
    // MARK: - Bucket selection

    func testBearingsSnapToTheNearestOfEightDirections() {
        let cases: [(bearing: Double, expected: SpriteDirection)] = [
            (0, .north), (22, .north), (23, .northEast), (45, .northEast), (67, .northEast), (68, .east),
            (90, .east), (135, .southEast), (180, .south), (225, .southWest), (270, .west), (315, .northWest),
            // The nw bucket runs to 337.5°, so 337 is still nw and 338 is north.
            (337, .northWest), (338, .north), (350, .north), (359.9, .north)
        ]
        for (bearing, expected) in cases {
            XCTAssertEqual(
                SpriteDirection.nearest(toBearing: bearing), expected,
                "\(bearing)° should select \(expected.rawValue)"
            )
        }
    }

    func testBucketSelectionWrapsAroundTheCompass() {
        // Negative and over-360 bearings normalize rather than crash or clamp.
        XCTAssertEqual(SpriteDirection.nearest(toBearing: -45), .northWest)
        XCTAssertEqual(SpriteDirection.nearest(toBearing: -90), .west)
        XCTAssertEqual(SpriteDirection.nearest(toBearing: 405), .northEast)
        XCTAssertEqual(SpriteDirection.nearest(toBearing: 720), .north)
    }

    func testEveryDirectionDeclaresItsOwnBearingAndShipsAnImage() throws {
        guard case let .directional(set)? = VehicleCatalog.artwork(id: VehicleCatalog.defaultSubjectId) else {
            return XCTFail("all eight car drawings must be bundled")
        }
        XCTAssertEqual(set.count, 8)
        for direction in SpriteDirection.allCases {
            XCTAssertNotNil(set[direction], "missing sprite for \(direction.rawValue)")
            XCTAssertEqual(SpriteDirection.nearest(toBearing: direction.degrees), direction)
        }
        // A shared canvas size keeps the car from pulsing as it turns.
        let sizes = Set(SpriteDirection.allCases.map { "\(set[$0]!.width)x\(set[$0]!.height)" })
        XCTAssertEqual(sizes.count, 1, "all eight drawings must share one canvas size")
    }

    // MARK: - Missing resources

    /// The fallback that used to be unreachable (2026-08-15). `Bundle.module`'s
    /// generated accessor calls `fatalError` when the bundle cannot be found, so
    /// `decodeAll`'s `return nil` and the marker renderer behind it could never
    /// run for the one failure they exist to handle — and it is the only
    /// `fatalError` on the shipped export path.
    ///
    /// A film with a seagull instead of a car is a degraded film. A trap is a
    /// crash mid-export, after minutes of rendering.
    func testAMissingSpriteBundleFallsBackToTheMarkerRatherThanTrapping() {
        // `resolved: nil` is what an unfindable resource bundle produces — the
        // case the generated `Bundle.module` accessor used to turn into a trap.
        let renderer = VehicleSubjectRenderer.make(
            style: RecapStyle(), subjectId: "car-red", lengthPx: 250, resolve: { _ in nil }
        )
        guard case let .marker(marker, _) = renderer.visual else {
            return XCTFail("a nil sprite set must select the vector marker, got \(renderer.visual)")
        }
        XCTAssertEqual(marker, RecapStyle().fallbackMarker)
        // Sized from the subject that could not be drawn, not from a number of
        // the marker's own (2026-08-29). The expectation changed because the
        // rule changed, not because it was failing.
        XCTAssertEqual(renderer.lengthPx, RecapStyle().fallbackMarkerLength(subjectLengthPx: 250))
    }

    /// **The stand-in may never be bigger than the thing it stands in for.**
    ///
    /// It was, from ADR 2026-08-27 until 2026-08-29: `fallbackMarkerLengthPx`
    /// was an absolute 170 while `export.subject_length_px` moved 225 → 157.5,
    /// so the fallback seagull rendered 12.5 px longer than the car. Nothing
    /// failed, because nothing tied the two numbers together.
    ///
    /// Swept across the sizes this project has actually shipped or tried, so the
    /// guard is about the rule and not about today's number.
    func testTheFallbackMarkerIsNeverLargerThanTheSubjectItReplaces() throws {
        for subjectLength in [CGFloat(112.5), 157.5, 170, 225, 300] {
            let renderer = VehicleSubjectRenderer.make(
                style: RecapStyle(), subjectId: "car-red", lengthPx: subjectLength, resolve: { _ in nil }
            )
            guard case .marker = renderer.visual else {
                return XCTFail("a nil sprite set must select the vector marker, got \(renderer.visual)")
            }
            XCTAssertLessThanOrEqual(
                renderer.lengthPx, subjectLength,
                "the fallback marker drew at \(renderer.lengthPx) for a \(subjectLength) subject"
            )
        }
    }

    /// The other half of the same contract: the resolver really does find the
    /// shipped bundle, so the fallback stays a fallback.
    func testTheShippedSpriteBundleResolves() throws {
        XCTAssertNotNil(
            VehicleResourceBundle.resolved,
            "the resource bundle lookup no longer finds the vehicle manifest"
        )
        guard case let .directional(set)? = VehicleCatalog.artwork(id: VehicleCatalog.defaultSubjectId) else {
            return XCTFail("the shipped car must load")
        }
        XCTAssertEqual(set.count, SpriteDirection.allCases.count)
    }

    /// The diagnostic approved on 2026-08-28, exercised rather than assumed.
    ///
    /// The lookup has failed twice in the field and been diagnosed neither time,
    /// and both times the only fact available was "not found". These two tests
    /// hold the message's contract: on failure it names every candidate and
    /// whether the nested bundle was **on disk**, which is what separates an
    /// install-timing fault from a packaging one; on success it says nothing.
    func testAFailedLookupNamesEveryCandidateAndWhetherItWasOnDisk() throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("kamome-bundle-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        let host = try XCTUnwrap(Bundle(url: empty), "a directory must be openable as a Bundle")

        let outcome = VehicleResourceBundle.resolve(hosts: [host])

        XCTAssertNil(outcome.bundle, "a host with no manifest must not resolve")
        XCTAssertTrue(
            outcome.trace.contains("KamomeCore_KamomeExportEngine.bundle: not on disk"),
            "the trace must say the nested bundle was absent, not merely that nothing resolved — got: \(outcome.trace)"
        )
        XCTAssertTrue(
            outcome.trace.contains("opened, no Vehicles/vehicles.json"),
            "the trace must also name the host tried as a candidate — got: \(outcome.trace)"
        )
    }

    /// The other half, and the one that keeps this off a successful render's
    /// console: a lookup that resolves reports nothing at all.
    func testAResolvedLookupTracesNothing() throws {
        let shipped = try XCTUnwrap(VehicleResourceBundle.resolved)
        let outcome = VehicleResourceBundle.resolve(hosts: [shipped])
        XCTAssertNotNil(outcome.bundle)
        XCTAssertEqual(outcome.trace, "", "a resolved lookup must leave nothing to log")
    }

    // MARK: - Rendering

    /// The heading is expressed by *which* drawing is chosen: headings in
    /// different buckets must render differently, and headings inside one bucket
    /// must render identically — no interpolation, no continuous rotation.
    func testHeadingSelectsTheDrawingWithoutRotatingIt() throws {
        func draw(heading: Double) throws -> Data {
            let context = try XCTUnwrap(CGContext(
                data: nil, width: widthPx, height: heightPx, bitsPerComponent: 8, bytesPerRow: 0,
                space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let surface = RenderSurface(
                context: context, widthPx: widthPx, heightPx: heightPx, scale: CGFloat(widthPx) / 1080
            ) { _, _ in CGPoint(x: self.widthPx / 2, y: self.heightPx / 2) }
            VehicleSubjectRenderer.make(style: RecapStyle(), lengthPx: 300).render(
                SubjectState(lat: -32, lon: 115.75, heading: heading),
                camera: CameraFrame(centerLat: -32, centerLon: 115.75, spanM: 1500, bearing: 0),
                into: surface
            )
            return try XCTUnwrap(pixels(try XCTUnwrap(context.makeImage())).data as Data?)
        }

        // Same bucket → the very same drawing, pixel for pixel.
        XCTAssertEqual(try draw(heading: 0), try draw(heading: 20), "20° is still the north drawing")
        XCTAssertEqual(try draw(heading: 90), try draw(heading: 100), "100° is still the east drawing")
        // Different buckets → different drawings.
        let byBucket = try SpriteDirection.allCases.map { try draw(heading: $0.degrees) }
        XCTAssertEqual(Set(byBucket).count, 8, "each of the eight headings must render its own drawing")
    }

    /// North-up means screen-up is always north, whatever way the trip runs — so
    /// the traveled trail lies in the route's true compass direction rather than
    /// always falling below the car. This is the invariant that replaced
    /// heading-up's "trail is always below".
    func testNorthUpKeepsTheMapFixedSoTheTrailFollowsTheCompass() async throws {
        let config = exportConfig()
        XCTAssertFalse(config.followHeadingUp, "the shipped config keeps the map north-up")
        let centerX = widthPx / 2, centerY = heightPx / 2
        let clear = vehicleHalfPx + 20

        // Northbound: travelled ground lies to the south — below on screen.
        let north = try makeTimeline(makeTrip(config: config), config: config)
        let northFrame = try await renderFrame(
            north, makeCompositor(north), at: config.targetDurationS / 2, config: config
        )
        try assertPixel(northFrame, col: centerX, row: centerY + clear, is: routeRGB, "north: trail lies south")
        try assertPixel(northFrame, col: centerX, row: centerY - clear, is: backgroundRGB, "north: nothing north yet")

        // Eastbound: travelled ground lies to the west — to the *left*, not below.
        let eastRoute = (0...10).map { RecapCoordinate(lat: -32.0, lon: 115.75 + Double($0) * 0.0009) }
        let east = try makeTimeline(makeTrip(route: eastRoute, config: config), config: config)
        let eastFrame = try await renderFrame(
            east, makeCompositor(east), at: config.targetDurationS / 2, config: config
        )
        try assertPixel(eastFrame, col: centerX - clear, row: centerY, is: routeRGB, "east: trail lies west")
        try assertPixel(eastFrame, col: centerX + clear, row: centerY, is: backgroundRGB, "east: nothing east yet")
    }
}
