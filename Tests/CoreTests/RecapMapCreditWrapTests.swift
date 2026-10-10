import CoreGraphics
import KamomeExportEngine
import XCTest

/// **A credit that does not fit one line wraps; it is never shrunk or cut**
/// (#114, ADR 2026-10-10-the-film-carries-copernicus-word-for-word). Beside
/// `RecapMapCreditTests`, which holds that the credit is drawn at all.
final class RecapMapCreditWrapTests: RecapRenderTestCase {
    /// **The longest credit Kamome can draw stays inside the frame** (#114).
    ///
    /// Copernicus's prescribed sentence made a European credit wider than a
    /// 1080 frame on one line, and a credit is never shrunk to fit, so it wraps.
    /// This reads pixels — the one property here that is *about* where ink
    /// lands — at the shipped 1080 × 1920, over a transparent frame, with every
    /// terrain source the world extent can reach.
    func testTheLongestCreditWrapsInsideTheFrame() throws {
        let width = 1080, height = 1920
        let credit = RecapMapAttribution.openFreeMap(minLat: -90, maxLat: 90, minLon: -180, maxLon: 180)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let surface = RenderSurface(context: context, widthPx: width, heightPx: height, scale: 1) { _, _ in .zero }
        let style = RecapStyle()
        RecapOverlayRenderer(style: style, resolver: StubResolver { _ in nil })
            .render(.mapCredit(credit), camera: CameraFrame(centerLat: 0, centerLon: 0, spanM: 1000, bearing: 0),
                    into: surface)

        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var inkRows = Set<Int>(), maxX = -1
        for row in 0..<height {
            for col in 0..<width where data[row * width * 4 + col * 4 + 3] > 0 {
                inkRows.insert(row)
                maxX = max(maxX, col)
            }
        }
        let margin = Int(style.mapCredit.marginPx)
        XCTAssertGreaterThanOrEqual(maxX, 0, "nothing was drawn")
        XCTAssertLessThan(maxX, width - margin, "the credit runs into the right margin or off the frame: \(credit)")
        let oneLine = style.mapCredit.fontPx + 2 * style.mapCredit.pillPaddingYPx
        XCTAssertGreaterThan(
            CGFloat(inkRows.count), oneLine * 2,
            "the world credit is too long for one line — if it fits now, this test no longer exercises the wrap"
        )
    }
}
