import CoreGraphics
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **How a reached town's ink is drawn** (ADR
/// 2026-10-29-the-film-inks-each-town-the-car-reaches): round the name, by a
/// pen, inside the room every name already keeps — so it never changes which
/// names are drawn — and the same, byte for byte, every time. Every place here
/// is made up (§0).
final class RecapPlaceInkDrawingTests: XCTestCase {
    private struct NoPhotos: RecapPhotoResolving {
        func image(for ref: PhotoRef, targetPx: Int) -> CGImage? { nil }
    }

    private let width = 540, height = 960
    private var scale: CGFloat { CGFloat(width) / 1080 }

    /// Twelve towns on a made-up grid, some close enough to crowd each other.
    private func towns(ink: (Int) -> Double) -> [RecapPlaceName] {
        let spots: [(Double, Double)] = [
            (0.00, 0.00), (0.01, 0.02), (0.03, -0.02), (0.05, 0.04), (0.06, 0.045), (-0.02, 0.05),
            (-0.04, -0.03), (-0.045, -0.02), (0.08, -0.05), (-0.07, 0.07), (0.02, 0.09), (-0.09, -0.08)
        ]
        let words = ["Ash", "Bay of Reeds", "Cove", "Dunmore Ridge", "Elk", "Fernhill", "Gull Point",
                     "Hartwell National Park", "Inlet", "Juniper", "Kestrel Falls", "Lowmoor"]
        return spots.enumerated().map { index, spot in
            RecapPlaceName(name: words[index], coordinate: RecapCoordinate(lat: spot.0, lon: spot.1), ink: ink(index))
        }
    }

    /// A surface whose camera has panned `offset` pixels: the dolly only
    /// translates, as it does between two frames of a film.
    private func surface(offset: CGPoint) throws -> RenderSurface {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.12, blue: 0.14, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let (centreX, centreY) = (CGFloat(width) / 2, CGFloat(height) / 2)
        return RenderSurface(context: context, widthPx: width, heightPx: height, scale: scale) { lat, lon in
            CGPoint(x: centreX + CGFloat(lon) * 4_000 + offset.x, y: centreY - CGFloat(lat) * 4_000 + offset.y)
        }
    }

    private func renderer(_ appearance: RecapAppearance = .dark, mark: RecapPlaceNameStyle.InkMark = .loop)
        -> RecapOverlayRenderer {
        var style = RecapStyle.modernMinimal(appearance)
        style.placeName.inkMark = mark
        return RecapOverlayRenderer(style: style, resolver: NoPhotos())
    }

    /// **The ink never changes which names are drawn**, at any frame of a
    /// camera move: the same names, in the same places, un-inked, half inked
    /// and inked — so the room the ink needs is kept round every name from the
    /// first frame, not when its town is reached. And on both shipped maps,
    /// for both marks, that room is still `clearancePx`, so the names drawn
    /// are exactly the ones drawn before the ink existed. (A loop that needed
    /// 23.6 px cost New Zealand's souvenir map one of its four names.)
    func testTheInkNeverChangesWhichNamesAreDrawn() throws {
        var counts = Set<Int>()
        for appearance in [RecapAppearance.dark, .light] {
            for mark in [RecapPlaceNameStyle.InkMark.loop, .underline] {
                let style = RecapStyle.modernMinimal(appearance).placeName
                var marked = style
                marked.inkMark = mark
                let room = RecapOverlayRenderer.nameClearancePx(marked)
                XCTAssertGreaterThanOrEqual(room, RecapOverlayRenderer.inkReachPx(marked), "\(appearance) \(mark)")
                XCTAssertEqual(room, style.clearancePx, "\(appearance) \(mark): the ink costs names")
                let drawing = renderer(appearance, mark: mark)
                for frame in 0..<90 {
                    let pan = try surface(offset: CGPoint(x: CGFloat(frame) * 6 - 270, y: CGFloat(frame) * 4 - 180))
                    func drawn(_ ink: @escaping (Int) -> Double) -> [String] {
                        drawing.drawnNames(towns(ink: ink), in: pan).map { "\($0.index) \($0.placed.rect)" }
                    }
                    let plain = drawn { _ in 0 }
                    XCTAssertEqual(drawn { _ in 1 }, plain, "frame \(frame)")
                    XCTAssertEqual(drawn { Double($0 % 3) / 2 }, plain, "frame \(frame)")
                    counts.insert(plain.count)
                }
            }
        }
        XCTAssertGreaterThan(counts.count, 1, "precondition: names enter and leave the frame as it pans")
        XCTAssertLessThan(try renderer().drawnNames(towns { _ in 0 }, in: surface(offset: .zero)).count, 12,
                          "precondition: some names crowd each other out")
    }

    /// **Two renders of the same frame are byte-identical**, and the ink is
    /// really drawn: the inked frame is not the plain one.
    func testTwoRendersOfTheSameFrameAreByteIdentical() throws {
        func render(_ ink: Double, _ appearance: RecapAppearance) throws -> Data {
            let target = try surface(offset: .zero)
            renderer(appearance).render(.placeNames(towns { _ in ink }, opacity: 1),
                                        camera: CameraFrame(centerLat: 0, centerLon: 0, spanM: 1, bearing: 0),
                                        into: target)
            let image = try XCTUnwrap(target.context.makeImage())
            return try XCTUnwrap(image.dataProvider?.data as Data?)
        }
        for appearance in [RecapAppearance.dark, .light] {
            XCTAssertEqual(try render(0.6, appearance), try render(0.6, appearance))
            XCTAssertEqual(try render(1, appearance), try render(1, appearance))
            XCTAssertNotEqual(try render(1, appearance), try render(0, appearance), "the ink drew nothing")
            XCTAssertNotEqual(try render(1, appearance), try render(0.6, appearance), "the pen did not move")
        }
    }

    /// **The ink stays inside the room every name keeps**, whatever the name:
    /// one line or two, three letters or a national park, loop or underline —
    /// and never reaches up to the dot, where the car parks.
    func testTheInkStaysInsideTheRoomEveryNameKeeps() {
        let token = RecapStyle.modernMinimal(.dark).placeName
        let line = token.fontPx * scale
        for mark in [RecapPlaceNameStyle.InkMark.loop, .underline] {
            var marked = token
            marked.inkMark = mark
            let room = RecapOverlayRenderer.nameClearancePx(marked) * scale
            let dotGap = (token.dotGapPx - token.dotRadiusPx / 2) * scale
            for index in 0..<400 {
                let lines = index % 3 == 0 ? 2 : 1
                let rect = CGRect(x: 100, y: 300, width: CGFloat(12 + (index * 37) % 420) * scale,
                                  height: line * (1 + CGFloat(lines - 1) * token.lineHeightEm))
                let path = RecapOverlayRenderer.inkPath(name: "Town \(index)", around: rect, token: marked, scale: scale)
                let allowed = rect.insetBy(dx: -room, dy: -room)
                for sample in path {
                    let ink = CGRect(x: sample.point.x - sample.halfWidth, y: sample.point.y - sample.halfWidth,
                                     width: 2 * sample.halfWidth, height: 2 * sample.halfWidth)
                    XCTAssertTrue(allowed.contains(ink), "\(mark) Town \(index): \(ink) outside \(allowed)")
                    XCTAssertLessThan(ink.maxY, rect.maxY + dotGap, "\(mark) Town \(index) reaches the dot")
                }
            }
        }
    }

    /// **A pen, not a stamp**: the stroke goes down along its length, the loop
    /// runs on past where it began and lifts away outside it — open, never
    /// joined — and each town's loop wanders its own way.
    func testTheLoopIsDrawnOnAlongItsLengthAndStaysOpen() throws {
        let token = RecapStyle.modernMinimal(.dark).placeName
        let rect = CGRect(x: 100, y: 300, width: 160, height: token.fontPx * scale)
        let path = RecapOverlayRenderer.inkPath(name: "Cove", around: rect, token: token, scale: scale)
        XCTAssertTrue(RecapOverlayRenderer.penDown(path, fraction: 0).isEmpty)
        XCTAssertEqual(RecapOverlayRenderer.penDown(path, fraction: 1), path)
        let half = RecapOverlayRenderer.penDown(path, fraction: 0.5)
        XCTAssertEqual(half.first, path.first)
        XCTAssertEqual(Double(half.count), Double(path.count) / 2, accuracy: 2)

        let first = try XCTUnwrap(path.first).point, last = try XCTUnwrap(path.last).point
        let walked = zip(path, path.dropFirst()).reduce(0) {
            $0 + hypot($1.1.point.x - $1.0.point.x, $1.1.point.y - $1.0.point.y)
        }
        let glyphs = (token.inkGlyphTopEm + token.inkGlyphBottomEm) * token.fontPx * scale
        let pad = token.inkPaddingPx * scale
        let once = InkLoop(halfWidth: rect.width / 2 + pad, halfHeight: glyphs / 2 + pad, pad: pad).perimeter
        XCTAssertGreaterThan(walked, once, "the pen goes once round, and on past where it began")
        XCTAssertGreaterThan(last.y, first.y, "the pen lifts away outside where it began")
        XCTAssertNotEqual(path, RecapOverlayRenderer.inkPath(name: "Elk", around: rect, token: token, scale: scale),
                          "two towns, one loop")
    }
}
