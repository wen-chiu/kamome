import CoreGraphics
@testable import KamomeExportEngine
import XCTest

/// **The opening title arrives and leaves; it does not cut** (2026-11-03).
/// It used to draw whole on frame 0 and vanish after the beat's last frame.
final class RecapTitleEntranceTests: RecapRenderTestCase {
    private let renderer = RecapOverlayRenderer(style: RecapStyle(), resolver: StubResolver { _ in nil })

    func testTheFirstFrameIsTheMapAlone() {
        let reveal = renderer.titleReveal(elapsedS: 0, holdS: 3)
        for value in [reveal.band, reveal.brand, reveal.name, reveal.rule, reveal.meta] {
            XCTAssertEqual(value, 0, accuracy: 0.001)
        }
    }

    func testTheStackArrivesInOrder() {
        let early = renderer.titleReveal(elapsedS: 0.6, holdS: 3)
        XCTAssertGreaterThan(early.brand, early.name, "the mark arrives before the name")
        XCTAssertGreaterThan(early.name, early.rule, "the name arrives before the rule")
        XCTAssertGreaterThanOrEqual(early.rule, early.meta, "and the dates come last")
    }

    func testTheStackSettlesThenLeaves() {
        let settled = renderer.titleReveal(elapsedS: 2, holdS: 3)
        let leaving = renderer.titleReveal(elapsedS: 2.99, holdS: 3)
        for value in [settled.band, settled.brand, settled.name, settled.rule, settled.meta, settled.exit] {
            XCTAssertEqual(value, 1, accuracy: 0.001, "settled before the exit")
        }
        XCTAssertLessThan(leaving.exit, 0.05, "and gone by the beat's last frame")
        XCTAssertEqual(leaving.name, 1, accuracy: 0.001, "leaving fades in place; it does not un-rise")
    }

    /// A beat shorter than the choreography's reference compresses it — the
    /// dates must still fully arrive before the exit begins.
    func testAShortBeatStillSettles() {
        let holdS = 0.4
        let peak = stride(from: 0.0, to: holdS, by: 0.01)
            .map { renderer.titleReveal(elapsedS: $0, holdS: holdS) }
            .map { $0.meta * $0.exit }.max() ?? 0
        XCTAssertEqual(peak, 1, accuracy: 0.001)
    }

    func testFrameZeroDrawsNoInk() throws {
        let width = 216, height = 384
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let surface = RenderSurface(context: context, widthPx: width, heightPx: height, scale: 0.2) { _, _ in .zero }
        let camera = CameraFrame(centerLat: 0, centerLon: 0, spanM: 1000, bearing: 0)
        renderer.render(.titleChrome(title: "Coast Road", subtitle: "May 3 – 9, 2024", elapsedS: 0, holdS: 3),
                        camera: camera, into: surface)
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        XCTAssertFalse((0..<(width * height)).contains { data[$0 * 4 + 3] > 0 }, "frame 0 drew the title")
        renderer.render(.titleChrome(title: "Coast Road", subtitle: "May 3 – 9, 2024", elapsedS: 2, holdS: 3),
                        camera: camera, into: surface)
        XCTAssertTrue((0..<(width * height)).contains { data[$0 * 4 + 3] > 0 }, "the settled title drew nothing")
    }
}
