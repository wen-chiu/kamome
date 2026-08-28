#if canImport(MapKit)
import CoreGraphics
import KamomeExportEngine
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

    /// The default is the behaviour every caller had before the parameter
    /// existed. It is what ships until Chiu judges a render, so it is pinned.
    func testTheDefaultProviderIsUnchangedFromBeforeTheParameterExisted() throws {
        let provider = MapKitSnapshotProvider()
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
}
#endif
