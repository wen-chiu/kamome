#if canImport(MapKit)
import CoreGraphics
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// **The points/pixels seam in `MapKitSnapshotProvider`** (2026-08-22).
///
/// `MKMapSnapshotterOptions.size` is in points, the image comes back at
/// `size × displayScale` pixels, and `snapshot.point(for:)` answers in points —
/// while `MapSnapshot`'s contract is pixels. The provider shipped at
/// `displayScale: 1`, where the two spaces coincide; raising it to enlarge place
/// labels makes them diverge by a constant factor.
///
/// **Nothing else in the suite can catch that.** The golden-frame gates render on
/// `FlatSnapshotProvider`, which has its own projection; the camera continuity
/// gate runs offline over `CameraFrame`s and never renders. A projection scaled
/// by a constant also survives casual inspection — every overlay is wrong by the
/// same fraction, which reads as a plausible still frame and only shows up as
/// drift in motion. So this is pinned as arithmetic, deterministically, with no
/// snapshot, no tiles and no network.
final class MapKitSnapshotScaleTests: XCTestCase {
    private let widthPx = 1080
    private let heightPx = 1920

    /// The canvas shrinks by exactly the scale, so the pixel output does not move.
    func testTheCanvasShrinksByTheScaleSoThePixelFrameIsUnchanged() throws {
        for scale in 1...3 {
            let size = try MapKitSnapshotProvider.pointSize(
                widthPx: widthPx, heightPx: heightPx, displayScale: scale
            )
            XCTAssertEqual(
                Int(size.width) * scale, widthPx,
                "a \(Int(size.width))pt canvas at scale \(scale) must render \(widthPx)px wide"
            )
            XCTAssertEqual(
                Int(size.height) * scale, heightPx,
                "a \(Int(size.height))pt canvas at scale \(scale) must render \(heightPx)px tall"
            )
        }
    }

    /// **The invariant that matters: the projection is scale-invariant in pixel
    /// space.** The same place must land on the same pixel at every scale — that
    /// is the whole reason overlays sit on the roads they name.
    ///
    /// Driven through fractions of the canvas rather than through real
    /// coordinates, because `point(for:)` is MapKit's and needs a live snapshot;
    /// what is under test is the correction wrapped around it.
    func testTheProjectionLandsOnTheSamePixelAtEveryScale() throws {
        // Fractions of the frame, including the centre and both diagonals.
        let fractions: [(x: Double, y: Double)] = [(0, 0), (0.5, 0.5), (0.25, 0.75), (1, 1)]
        for fraction in fractions {
            var pixels: [CGPoint] = []
            for scale in 1...3 {
                let size = try MapKitSnapshotProvider.pointSize(
                    widthPx: widthPx, heightPx: heightPx, displayScale: scale
                )
                // Where MapKit would answer for that place, in its own points.
                let inPoints = CGPoint(x: size.width * fraction.x, y: size.height * fraction.y)
                pixels.append(MapKitSnapshotProvider.pixel(inPoints, displayScale: scale))
            }
            let expected = CGPoint(x: Double(widthPx) * fraction.x, y: Double(heightPx) * fraction.y)
            for (index, pixel) in pixels.enumerated() {
                XCTAssertEqual(
                    pixel.x, expected.x, accuracy: 0.001,
                    "fraction \(fraction) at scale \(index + 1) must project to the same pixel x"
                )
                XCTAssertEqual(
                    pixel.y, expected.y, accuracy: 0.001,
                    "fraction \(fraction) at scale \(index + 1) must project to the same pixel y"
                )
            }
        }
    }

    /// A scale that does not divide the frame is refused, not rounded.
    ///
    /// Rounding would put every overlay a fraction of a percent off its road —
    /// consistently enough to look deliberate, which is the failure this seam
    /// exists to prevent (Arch.md §5: no silent fallbacks).
    func testAScaleThatDoesNotDivideTheFrameIsRefused() {
        XCTAssertThrowsError(
            try MapKitSnapshotProvider.pointSize(widthPx: 1080, heightPx: 1920, displayScale: 7),
            "1080 is not a whole number of points at scale 7"
        ) { error in
            XCTAssertTrue(error is MapKitSnapshotProvider.ScaleError, "got \(error)")
        }
        XCTAssertThrowsError(
            try MapKitSnapshotProvider.pointSize(widthPx: 1080, heightPx: 1920, displayScale: 0),
            "a zero scale would divide by zero"
        )
    }

    /// **MapKit rastering at a scale nobody asked for is tolerated; stretching
    /// is not** (measured 2026-08-22, `MapKitSnapshotProbeTests`).
    ///
    /// An Iceland render asked for 2 and got a 1620x2880px image for its
    /// 540x960pt canvas — 3x. That is harmless: `point(for:)` answers in the
    /// canvas, so the correction is still `widthPx / canvasWidth`, and the
    /// compositor resamples the bigger image into the same frame. A raster that
    /// is not *uniform*, though, has no single factor at all, and every overlay
    /// would sit wrong on one axis.
    func testAnUnrequestedRasterScaleIsToleratedButAStretchedOneIsNot() throws {
        let canvas = CGSize(width: 540, height: 960)
        XCTAssertEqual(
            try MapKitSnapshotProvider.rasterScale(imageWidth: 1080, imageHeight: 1920, canvas: canvas),
            2, accuracy: 0.001, "the requested scale"
        )
        XCTAssertEqual(
            try MapKitSnapshotProvider.rasterScale(imageWidth: 1620, imageHeight: 2880, canvas: canvas),
            3, accuracy: 0.001, "the scale the Iceland render actually got — uniform, so usable"
        )
        XCTAssertThrowsError(
            try MapKitSnapshotProvider.rasterScale(imageWidth: 1620, imageHeight: 1920, canvas: canvas),
            "3x across and 2x down cannot be corrected by one factor"
        ) { error in
            XCTAssertTrue(error is MapKitSnapshotProvider.ScaleError, "got \(error)")
        }
        XCTAssertThrowsError(
            try MapKitSnapshotProvider.rasterScale(imageWidth: 270, imageHeight: 480, canvas: canvas),
            "an image smaller than its own canvas is not a raster of it"
        )
    }

    /// The default **display scale** is the behaviour every caller had before the
    /// parameter existed. It is what ships until Chiu judges a render, so it is
    /// pinned.
    ///
    /// The appearance is passed explicitly because as of 2026-08-28 it has no
    /// default: the film follows the device, so an implicit `.light` here would be
    /// a gate silently asserting one half of a pair. `.light` is named rather than
    /// inherited — which is the whole point.
    func testTheDefaultProviderIsUnchangedFromBeforeTheParameterExisted() throws {
        let provider = MapKitSnapshotProvider(appearance: .light)
        XCTAssertEqual(provider.displayScale, 1, "the shipping path must still be 1 point == 1 pixel")
        let size = try MapKitSnapshotProvider.pointSize(
            widthPx: widthPx, heightPx: heightPx, displayScale: provider.displayScale
        )
        XCTAssertEqual(size, CGSize(width: widthPx, height: heightPx))
        let point = CGPoint(x: 123.5, y: 456.25)
        XCTAssertEqual(
            MapKitSnapshotProvider.pixel(point, displayScale: provider.displayScale), point,
            "at scale 1 the correction must be exactly the identity"
        )
    }

    // MARK: - The frames that cannot be drawn (2026-09-01)

    /// **The crash.** `MKCoordinateRegion(center:latitudinalMeters:longitudinalMeters:)`
    /// raises an Objective-C exception — process death, invisible to every Swift
    /// `catch` — when the span it computes is taller than the planet. A 9:16
    /// frame gets there at ~11,250 km of *width*, because its height is 1.778x
    /// that. Taiwan → Iceland is exactly that frame.
    ///
    /// Pinned as arithmetic for the same reason the seam above is: no live
    /// substrate test can assert this, because reaching the bug is the crash.
    func testAFrameTallerThanThePlanetIsRefusedRatherThanHandedToMapKit() throws {
        // Isolated at the equator, where a degree of longitude is at its widest
        // and the zoom floor therefore does NOT bind: 12,000 km is 107.8 degrees
        // of longitude (inside 109) and 191.7 of latitude (outside 180). Which
        // limit binds first is a function of latitude — see the test below.
        XCTAssertThrowsError(try MapKitSnapshotProvider.region(
            centerLat: 0, centerLon: 0, spanM: 12_000_000, widthPx: widthPx, heightPx: heightPx
        ), "191.7 degrees of latitude must be refused even though the longitude is legal") { error in
            XCTAssertTrue(
                (error as? MapKitSnapshotProvider.UnframableError)?
                    .description.contains("the planet has 180") == true,
                "the height limit must be the one reported here: \(error)"
            )
        }
        XCTAssertNoThrow(try MapKitSnapshotProvider.region(
            centerLat: 0, centerLon: 0, spanM: 11_000_000, widthPx: widthPx, heightPx: heightPx
        ), "11,000 km at the equator is inside both limits and must still be framed")

        XCTAssertThrowsError(try MapKitSnapshotProvider.region(
            centerLat: 36.94, centerLon: 61.96, spanM: 15_909_000, widthPx: widthPx, heightPx: heightPx
        ), "the Taipei-Paris frame is 254 degrees of latitude tall and must be refused") { error in
            let unframable = error as? MapKitSnapshotProvider.UnframableError
            XCTAssertNotNil(unframable, "the refusal must be typed, so a caller can choose another form")
            XCTAssertTrue(
                unframable?.description.contains("the planet has 180") == true,
                "the refusal must say which limit was hit: \(String(describing: unframable))"
            )
        }
    }

    /// **The zoom floor.** Past ~109 degrees of longitude MapKit returns the same
    /// picture however far out it is asked, so a wider frame is not a wider
    /// picture — it is the same one with both subjects outside it. Measured
    /// 2026-09-01; refused rather than clamped, because a clamp is the silent
    /// fallback that produced the finding in the first place.
    func testAFrameWiderThanMapKitWillDrawIsRefusedRatherThanClamped() throws {
        // At the equator a degree of longitude is at its widest, so this is the
        // most forgiving latitude for the check — and 109 degrees is 12,133 km.
        XCTAssertThrowsError(try MapKitSnapshotProvider.region(
            centerLat: 0, centerLon: 0, spanM: 13_000_000, widthPx: widthPx, heightPx: heightPx
        )) { error in
            XCTAssertNotNil(error as? MapKitSnapshotProvider.UnframableError)
        }

        // **Which limit binds first is a function of latitude**, and that is the
        // whole reason the threshold is in degrees. The same 9,000 km span is
        // 80.8 degrees of longitude at the equator and 161.7 at 60 north — legal
        // there, refused here — while its height, 143.7 degrees, never moves.
        let span = 9_000_000.0
        XCTAssertNoThrow(try MapKitSnapshotProvider.region(
            centerLat: 0, centerLon: 0, spanM: span, widthPx: widthPx, heightPx: heightPx
        ), "80.8 degrees of longitude is inside the floor")
        XCTAssertThrowsError(try MapKitSnapshotProvider.region(
            centerLat: 60, centerLon: 0, spanM: span, widthPx: widthPx, heightPx: heightPx
        ), "the identical span is 161.7 degrees of longitude at 60 north") { error in
            XCTAssertTrue(
                (error as? MapKitSnapshotProvider.UnframableError)?
                    .description.contains("MapKit draws at most") == true,
                "the zoom floor must be the one reported here: \(error)"
            )
        }
    }

    /// Every frame the shipping film actually asks for must still be drawable —
    /// otherwise this guard is a regression rather than a guard. The widest
    /// measured country beat is Japan at 2,111 km (`miyakojima`); the widest
    /// establishing extent any test uses is 2,818 km.
    func testEveryFrameTheShippedFilmAsksForIsStillFramable() throws {
        for (label, spanM, lat) in [
            ("a body span", 20_000.0, 24.4), ("Taiwan, the country beat", 285_600.0, 23.6),
            ("Japan, the country beat", 2_111_600.0, 34.8), ("the widest test extent", 2_817_800.0, 36.0)
        ] {
            XCTAssertNoThrow(
                try MapKitSnapshotProvider.region(
                    centerLat: lat, centerLon: 121, spanM: spanM, widthPx: widthPx, heightPx: heightPx
                ),
                "\(label) is a frame the film renders today and must not start throwing"
            )
        }
    }

    /// The substrate declares the limit it enforces, so a caller can choose the
    /// film's form *before* taking a snapshot rather than discovering it per
    /// frame. Same rule as `fixedAppearance`.
    func testTheProviderDeclaresTheLimitItEnforces() {
        let declared = MapKitSnapshotProvider(appearance: .light).capabilities.maxFramableLongitudeDeg
        XCTAssertEqual(
            declared, MapKitSnapshotProvider.maxLongitudeSpanDeg,
            "a declaration that disagrees with the refusal is worse than no declaration"
        )
    }
}
#endif
