import CoreGraphics
@testable import KamomeExportEngine
import XCTest

/// **The opening title stands clear of the map credit, however tall it wraps**
/// (2026-11-03). The credit wraps to as many lines as its licence needs (#114),
/// and the title stack used to be placed as though it were one line — so on a
/// European film the dates sat under Copernicus's sentence.
final class RecapTitleCreditClearanceTests: RecapRenderTestCase {
    func testTheTitleStackClearsTheTallestCredit() throws {
        let credits = [
            RecapMapAttribution.openFreeMapBase,
            RecapMapAttribution.openFreeMap(minLat: 45, maxLat: 46, minLon: 5, maxLon: 6),
            RecapMapAttribution.openFreeMap(minLat: -90, maxLat: 90, minLon: -180, maxLon: 180)
        ]
        var style = RecapStyle()
        // The band is a wash over the whole bottom of the frame; with it clear,
        // the only ink left is the type, which is what has to stand clear.
        style.titleBandOpacity = 0
        for credit in credits {
            let titleRows = try inkRows(style: style, credit: credit) {
                .titleChrome(
                    title: "沿著海岸線慢慢開的一整個星期", subtitle: "2024年5月3日至9日 · 7 天 · 840 km",
                    elapsedS: 2, holdS: 3
                )
            }
            let creditRows = try inkRows(style: style, credit: credit) { .mapCredit(credit) }
            let titleLowest = try XCTUnwrap(titleRows.max(), "the title drew nothing")
            let creditHighest = try XCTUnwrap(creditRows.min(), "the credit drew nothing")
            XCTAssertGreaterThanOrEqual(
                creditHighest - titleLowest, Int(style.titleStack.creditClearancePx / 2),
                "the title's lowest ink (row \(titleLowest)) is on or near the credit (top row \(creditHighest)): \(credit)"
            )
        }
    }

    /// Image rows (top-down) holding any ink, for one overlay drawn alone at
    /// the shipped 1080 × 1920 on a surface that carries `credit`.
    private func inkRows(
        style: RecapStyle, credit: String, _ content: () -> OverlayContent
    ) throws -> Set<Int> {
        let width = 1080, height = 1920
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        var surface = RenderSurface(context: context, widthPx: width, heightPx: height, scale: 1) { _, _ in .zero }
        surface.mapCredit = credit
        RecapOverlayRenderer(style: style, resolver: StubResolver { _ in nil })
            .render(content(), camera: CameraFrame(centerLat: 0, centerLon: 0, spanM: 1000, bearing: 0), into: surface)
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var rows = Set<Int>()
        for row in 0..<height {
            for col in 0..<width where data[row * width * 4 + col * 4 + 3] > 0 {
                rows.insert(row)
                break
            }
        }
        return rows
    }
}
