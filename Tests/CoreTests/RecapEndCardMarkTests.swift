import CoreGraphics
import Foundation
import ImageIO
import KamomeConfig
import KamomeExportEngine
import UniformTypeIdentifiers
import XCTest

/// **The end card's brand mark is the bird** (#124, `Docs/release-readiness.md`
/// C4, `Docs/handoff-marker-badge.md` 6d).
///
/// `RecapChromeTests` counts lit pixels on the end card, which the wordmark alone
/// would satisfy, and `VehicleMarker.seagull` has three consumers: restyling it
/// for one of them once nearly turned the wordmark's bird into a blue disc, and
/// only a reader of the call graph caught it.
///
/// This renders the shipped end card (`modernMinimal`, both appearances) at the
/// film's own 1080 × 1920, finds the mark — the topmost run of pixels in the
/// accent colour, the tagline being the only other thing drawn in it — and holds
/// its **shape** to a baseline mask: a wide, thin, two-lobed stroke, not a disc
/// and not nothing.
///
/// ⚠️ **What it cannot see:** the base under the card is the flat provider, so
/// this says nothing about how the bird reads over a real map; and the baseline
/// is Chiu-visible only as far as its picture is — `KAMOME_RENDER_OUT=<dir>`
/// writes the end card and the mask it read from it.
final class RecapEndCardMarkTests: RecapRenderTestCase {
    private static let frameW = 1080
    private static let frameH = 1920

    /// The bird on a 32 × 16 grid over its own bounding box: `#` where at least half of the
    /// cell is accent-coloured. **A baseline agreed by eye** from
    /// the render in the PR, not derived from the drawing code: a mask read off
    /// `drawSeagull` would follow it wherever it was restyled.
    private static let baseline = [
        ".........####......####.........",
        ".......########...#######.......",
        "......##########.#########......",
        ".....######################.....",
        ".....#######################....",
        "....######..########..######....",
        "...######....######....######...",
        "...#####.....######.....######..",
        "..######......####.......#####..",
        "..#####........###.......######.",
        ".#####....................#####.",
        ".#####....................######",
        "#####......................#####",
        "#####......................#####",
        "####........................####",
        ".##..........................##."
    ]

    private struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        func rgb(_ col: Int, _ row: Int) -> RGB {
            let offset = (row * width + col) * 4
            return RGB(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
        }

        /// Within 40 of `target` on every channel: antialiasing and the soft shadow
        /// stay out, the stroke's own colour stays in.
        func isNear(_ target: RGB, _ col: Int, _ row: Int) -> Bool {
            let sample = rgb(col, row)
            return max(abs(sample.red - target.red), abs(sample.green - target.green), abs(sample.blue - target.blue)) <= 40
        }
    }

    private func bitmap(_ image: CGImage) throws -> Bitmap {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Bitmap(width: image.width, height: image.height, bytes: bytes)
    }

    private func endFrame(_ appearance: RecapAppearance, shareURL: String? = nil) async throws -> (CGImage, RecapStyle) {
        let config = exportConfig()
        let style = RecapStyle.modernMinimal(appearance).withEndCard("full")
        let timeline = try makeTimeline(
            makeTrip(stops: [StopSpec(routeIndex: 5)], shareURL: shareURL, config: config), config: config
        )
        let compositor = FrameCompositor(
            timeline: timeline, subject: VehicleSubjectRenderer.make(style: style, lengthPx: 300),
            overlay: RecapOverlayRenderer(style: style, resolver: StubResolver { _ in nil }),
            widthPx: Self.frameW, heightPx: Self.frameH, crossingSubject: nil, flightSubject: nil
        )
        let time = config.targetDurationS - 0.5
        let camera = timeline.cameraFrame(atTime: time)
        let base = appearance == .dark
            ? FlatSnapshotProvider(red: 0.09, green: 0.11, blue: 0.16)
            : FlatSnapshotProvider(red: 0.93, green: 0.93, blue: 0.91)
        let snapshot = try await base.snapshot(
            CameraFrame(centerLat: camera.centerLat, centerLon: camera.centerLon, spanM: camera.spanM, bearing: camera.bearing),
            map: MapState(), widthPx: Self.frameW, heightPx: Self.frameH
        )
        return (try compositor.render(atTime: time, background: RecapBackground(current: snapshot), credit: nil), style)
    }

    /// The box of the topmost run of rows carrying accent pixels; the run ends at
    /// 40 blank rows (the title band sits between the mark and the tagline).
    private func markBox(_ bitmap: Bitmap, accent: RGB) -> CGRect? {
        var first: Int?
        var last = 0
        var blank = 0
        var minCol = bitmap.width
        var maxCol = 0
        for row in 0 ..< bitmap.height {
            let cols = (0 ..< bitmap.width).filter { bitmap.isNear(accent, $0, row) }
            guard let lo = cols.first, let hi = cols.last else {
                blank += 1
                if first != nil, blank > 40 { break }
                continue
            }
            first = first ?? row
            (last, blank) = (row, 0)
            (minCol, maxCol) = (min(minCol, lo), max(maxCol, hi))
        }
        guard let top = first else { return nil }
        return CGRect(x: minCol, y: top, width: maxCol - minCol + 1, height: last - top + 1)
    }

    /// The accent-coloured pixels of the topmost run, as a grid over its box.
    private func markMask(_ image: CGImage, accent: CGColor) throws -> (grid: [String], box: CGRect)? {
        let bitmap = try bitmap(image)
        let parts = (accent.components ?? []).prefix(3).map { Int(($0 * 255).rounded()) }
        guard parts.count == 3 else { return nil }
        let target = RGB(red: parts[0], green: parts[1], blue: parts[2])
        guard let box = markBox(bitmap, accent: target) else { return nil }
        let grid = (0 ..< 16).map { cell in
            String((0 ..< 32).map { slot -> Character in
                let (left, right) = (Int(box.minX) + slot * Int(box.width) / 32, Int(box.minX) + (slot + 1) * Int(box.width) / 32)
                let top = Int(box.minY) + cell * Int(box.height) / 16
                let bottom = Int(box.minY) + (cell + 1) * Int(box.height) / 16
                let cols = left ..< max(right, left + 1)
                let rows = top ..< max(bottom, top + 1)
                let cells = rows.flatMap { row in cols.map { (row, $0) } }
                let hits = cells.filter { bitmap.isNear(target, $0.1, $0.0) }.count
                return Double(hits) / Double(max(cells.count, 1)) >= 0.5 ? "#" : "."
            })
        }
        return (grid, box)
    }

    private func overlap(_ lhs: [String], _ rhs: [String]) -> Double {
        var both = 0
        var either = 0
        for (rowA, rowB) in zip(lhs, rhs) {
            for (cellA, cellB) in zip(rowA, rowB) {
                if cellA == "#" && cellB == "#" { both += 1 }
                if cellA == "#" || cellB == "#" { either += 1 }
            }
        }
        return either == 0 ? 0 : Double(both) / Double(either)
    }

    func testTheEndCardsMarkIsTheBirdInBothAppearances() async throws {
        for appearance in [RecapAppearance.light, .dark] {
            let (frame, style) = try await endFrame(appearance)
            let mark = try XCTUnwrap(
                try markMask(frame, accent: style.chromeAccentColor),
                "no accent-coloured mark on the \(appearance) end card"
            )
            print("END_CARD_MARK \(appearance) box=\(mark.box)\n" + mark.grid.joined(separator: "\n"))
            try writeStills(frame, mask: mark, name: "end-card-\(appearance)")

            // A gull is wide and thin; a disc is square and full. Both are asserted
            // against the same baseline the shape check uses, so this is the
            // legible reason a failure gives before the grid comparison does.
            XCTAssertGreaterThan(mark.box.width / mark.box.height, 1.5, "\(appearance): the mark is not wide, like a gull")
            let filled = Double(mark.grid.joined().filter { $0 == "#" }.count) / Double(32 * 16)
            XCTAssertLessThan(filled, 0.6, "\(appearance): the mark is a filled shape, like a disc")
            XCTAssertGreaterThan(
                overlap(mark.grid, Self.baseline), 0.8,
                "\(appearance): the end card's mark is not the gull. Got:\n" + mark.grid.joined(separator: "\n")
            )
        }
    }

    /// The control: with a share URL the mark is a QR, which the accent scan must
    /// not mistake for the bird — the scan finds the bird, not "something".
    func testAShareCodeInsteadOfTheMarkIsNotTheBird() async throws {
        let (frame, style) = try await endFrame(.dark, shareURL: "https://kamome.app/r/test")
        let mark = try markMask(frame, accent: style.chromeAccentColor)
        XCTAssertLessThan(overlap(mark?.grid ?? [], Self.baseline), 0.5, "a QR passed for the gull")
    }

    private func writeStills(_ frame: CGImage, mask: (grid: [String], box: CGRect), name: String) throws {
        guard let dir = HarnessEnv.value("KAMOME_RENDER_OUT") else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, frame, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
