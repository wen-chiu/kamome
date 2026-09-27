import CoreGraphics
@testable import KamomeExportEngine
import XCTest

/// **A long name takes two lines instead of shrinking under the date line**
/// (Chiu 2026-09-27). One line down to `titleMinFontPx`; past that, two lines of
/// even width, never cut off.
final class RecapTitleLayoutTests: XCTestCase {
    private let style = RecapStyle()
    private lazy var renderer = RecapOverlayRenderer(style: style, resolver: NoPhotos())
    /// The title card's own width: the frame less `titleSideMarginScale` margins.
    private lazy var maxWidth = 1080 - style.cardMarginPx * style.titleSideMarginScale * 2

    private struct NoPhotos: RecapPhotoResolving {
        func image(for ref: PhotoRef, targetPx: Int) -> CGImage? { nil }
    }

    private func surface() throws -> RenderSurface {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 1080, height: 1920, bitsPerComponent: 8, bytesPerRow: 0,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return RenderSurface(context: context, widthPx: 1080, heightPx: 1920, scale: 1) { _, _ in .zero }
    }

    private func layout(_ title: String) throws -> RecapTitleLayout {
        renderer.titleLayout(title, maxWidth: maxWidth, in: try surface())
    }

    func testAShortNameIsOneLineAtFullSize() throws {
        XCTAssertEqual(try layout("北海道夏天"), RecapTitleLayout(lines: ["北海道夏天"], fontPx: style.titleFontPx))
    }

    func testANameThatFitsAboveTheFloorStaysOnOneLine() throws {
        let result = try layout("2026 西澳公路旅行：伯斯到瑪格麗特河")
        XCTAssertEqual(result.lines.count, 1)
        XCTAssertGreaterThanOrEqual(result.fontPx, style.titleMinFontPx)
    }

    func testALongChineseNameTakesTwoLinesAtOrAboveTheFloor() throws {
        let title = "跟爸媽一起的冰島環島公路旅行，從雷克雅維克出發繞一整圈回來"
        let result = try layout(title)
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.lines.joined(), title, "nothing is cut off")
        XCTAssertGreaterThanOrEqual(result.fontPx, style.titleMinFontPx)
        XCTAssertFalse(result.lines[1].hasPrefix("，"), "no line starts with closing punctuation")
        let surface = try surface()
        for line in result.lines {
            XCTAssertLessThanOrEqual(renderer.textWidth(line, fontPx: result.fontPx, in: surface), maxWidth + 0.5)
        }
    }

    func testALongEnglishNameBreaksAtASpace() throws {
        let result = try layout("Iceland Ring Road with Mum and Dad, Summer 2026")
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(result.lines.joined(separator: " "), "Iceland Ring Road with Mum and Dad, Summer 2026")
        XCTAssertGreaterThanOrEqual(result.fontPx, style.titleMinFontPx)
    }

    /// Too long for two lines at the floor: it shrinks further rather than lose words.
    func testANameTooLongForTwoLinesShrinksRatherThanTruncates() throws {
        let title = String(repeating: "冰島環島公路旅行", count: 6)
        let result = try layout(title)
        XCTAssertEqual(result.lines.joined(), title)
        XCTAssertLessThan(result.fontPx, style.titleMinFontPx)
    }

    /// A long word with nowhere to break keeps the old single-line shrink.
    func testANameWithNoBreakKeepsOneLine() throws {
        XCTAssertEqual(try layout(String(repeating: "W", count: 60)).lines.count, 1)
    }
}
