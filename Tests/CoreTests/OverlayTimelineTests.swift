import KamomeConfig
import KamomeExportEngine
import XCTest

/// Overlay events are the timeline layer between CameraPath holds and the
/// frame renderer (decisions.md 2026-07-17).
final class OverlayTimelineTests: XCTestCase {
    private let route: [CameraPath.Point] = (0...10).map {
        CameraPath.Point(lat: -32.0 + Double($0) * 0.0009, lon: 115.75)
    }

    private var config: TrackingConfig.Export {
        TrackingConfig.Export(
            targetDurationS: 30, fps: 30, stopHoldS: 1.5, maxHoldFraction: 0.5,
            gifFps: 12, gifWidthPx: 480, frameWidthPx: 1080, frameHeightPx: 1920,
            cameraSpanM: 1500, wideSpanPadding: 1.15, zoomTransitionS: 0.8, followHeadingUp: false,
            keyframeIntervalFrames: 15, titleCardS: 2.5, endCardS: 3, videoBitrateMbps: 5
        )
    }

    private func path(stops: [CameraPath.Point]) throws -> CameraPath {
        try XCTUnwrap(CameraPath(route: route, stops: stops, config: config))
    }

    func testHoldsExposeOneWindowPerStopInPlaybackOrder() throws {
        // Stops passed out of route order: holds must come back in playback order.
        let path = try path(stops: [route[7], route[3]])
        let holds = path.holds

        XCTAssertEqual(holds.count, 2)
        XCTAssertEqual(holds.map(\.stopIndex), [1, 0], "second stop passed lies earlier on the route")
        XCTAssertLessThan(holds[0].startS, holds[1].startS)
        for hold in holds {
            XCTAssertEqual(hold.endS - hold.startS, 1.5, accuracy: 1e-9)
            // The camera is actually holding this stop throughout the window.
            let mid = path.position(atTime: (hold.startS + hold.endS) / 2)
            XCTAssertEqual(mid.holdingStopIndex, hold.stopIndex)
        }
    }

    func testStopCardEventsMirrorHoldsWhenPhotosEnabled() throws {
        let holds = try path(stops: [route[5]]).holds
        let events = OverlayTimeline.build(holds: holds, config: config, photosEnabled: true)

        let stopEvents = events.filter {
            if case .stopCard = $0.kind { return true } else { return false }
        }
        XCTAssertEqual(stopEvents.count, 1)
        XCTAssertEqual(stopEvents[0].kind, .stopCard(stopIndex: 0))
        XCTAssertEqual(stopEvents[0].startS, holds[0].startS)
        XCTAssertEqual(stopEvents[0].endS, holds[0].endS)
    }

    func testTitleAndEndCardsFrameTheVideo() throws {
        let events = OverlayTimeline.build(holds: [], config: config, photosEnabled: true)

        XCTAssertEqual(events.map(\.kind), [.titleCard, .endCard])
        XCTAssertEqual(events[0].startS, 0)
        XCTAssertEqual(events[0].endS, 2.5, "title card runs title_card_s from the open")
        XCTAssertEqual(events[1].startS, 27, "end card owns the last end_card_s")
        XCTAssertEqual(events[1].endS, 30)
    }

    func testPhotosDisabledDropsStopCardsButKeepsTripChrome() throws {
        // decisions.md 2026-07-17: the S5 toggle removes photo moments; the
        // title/end cards (and the share hook on the end card) stay.
        let holds = try path(stops: [route[3], route[5], route[7]]).holds
        let events = OverlayTimeline.build(holds: holds, config: config, photosEnabled: false)
        XCTAssertEqual(events.map(\.kind), [.titleCard, .endCard])
    }

    func testActiveSelectsTheEventUnderThePlayhead() throws {
        let holds = try path(stops: [route[3], route[7]]).holds
        let events = OverlayTimeline.build(holds: holds, config: config, photosEnabled: true)

        let during = OverlayTimeline.active(in: events, atTime: holds[0].startS + 0.5)
        XCTAssertEqual(during.map(\.kind), [.stopCard(stopIndex: 0)])

        let between = OverlayTimeline.active(in: events, atTime: (holds[0].endS + holds[1].startS) / 2)
        XCTAssertTrue(between.isEmpty)

        // End is exclusive: the frame at endS is back to travel.
        XCTAssertTrue(OverlayTimeline.active(in: events, atTime: holds[0].endS).isEmpty)
    }
}
