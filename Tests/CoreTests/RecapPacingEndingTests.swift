import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// The ending (Chiu 2026-09-29): 「結尾底圖的背景的大小我覺得很好，在出現結尾字幕之前可以多停1~2秒。
/// 給使用者看一下完整旅程軌跡總共跑了哪些地方」. Shares `RecapPacingTests`' trip.
extension RecapPacingTests {
    private func shippedExport() throws -> TrackingConfig.Export {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
        return try TrackingConfigLoader.load(contentsOf: url).export
    }

    /// **The whole route holds, revealed, for `end_route_hold_s` before the end
    /// card** — the reveal has finished and not one frame moves until the card.
    func testTheRevealedRouteHoldsBeforeTheEndCard() throws {
        let config = try shippedExport()
        XCTAssertGreaterThan(config.endRouteHoldS, 0, "the shipped film holds its route")
        let line = try XCTUnwrap(LinearTimeline(trip: trip(photoCounts: [3, 3, 3]), config: config))
        let cardS = line.durationS - config.endCardS
        let held = line.cameraFrame(atTime: cardS - config.endRouteHoldS)
        let step = 1.0 / Double(config.fps)
        for time in stride(from: cardS - config.endRouteHoldS, to: cardS, by: step) {
            let frame = line.cameraFrame(atTime: time)
            XCTAssertEqual(frame.spanM, held.spanM, accuracy: 1e-6, "the route moved at t=\(time)")
            XCTAssertEqual(frame.centerLat, held.centerLat, accuracy: 1e-9, "the route moved at t=\(time)")
            XCTAssertEqual(frame.centerLon, held.centerLon, accuracy: 1e-9, "the route moved at t=\(time)")
        }
        // And it is the reveal's end: the camera was still moving half-way through it.
        let midReveal = line.cameraFrame(atTime: cardS - config.endRouteHoldS - config.endRevealS / 2)
        XCTAssertNotEqual(midReveal.spanM, held.spanM, accuracy: 1, "no reveal before the hold")
    }
}
