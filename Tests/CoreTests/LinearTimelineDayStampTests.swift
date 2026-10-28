import KamomeConfig
@testable import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// **The day stamp, as the timeline tells it** (ADR 2026-10-28-a-new-day-presses-a-stamp-into-the-film):
/// one stamp for each turn of the day, landing in the HUD as the day's first stop
/// arrives, never over a photograph or a card, never adding film time, and never
/// showing the day twice in one frame. Drawing is `RecapDayStampRenderTests`'.
final class LinearTimelineDayStampTests: LinearTimelineTestCase {
    private let stamp = DayStampConfig(clearS: 0.25, pressS: 0.35, holdS: 0.9, landS: 0.55, minS: 1.4)

    private struct Frame {
        let time: Double
        let contents: [OverlayContent]

        var hud: (day: String, stamp: RecapDayStamp?)? {
            for case let .hud(day, _, _, stamp) in contents { return (day, stamp) }
            return nil
        }
    }

    /// Three stops on three days — or, with `days`, whichever days are given.
    private func trip(days: [String], config: TrackingConfig.Export, photos: Int = 3) -> RecapTrip {
        let route = (0...40).map { RecapCoordinate(lat: -32.0 + Double($0) * 0.01, lon: 115.75) }
        let deck = RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS,
            labelLeadS: config.deckLabelLeadS, photoMinHoldS: config.deckPhotoMinHoldS
        )
        let stops = days.enumerated().map { index, day in
            RecapTrip.Stop(
                coordinate: route[(index + 1) * 9], name: "Stop \(index + 1)", dayLabel: day, detail: nil,
                photos: (0..<photos).map { .asset("s\(index)-\($0)") }, dwellS: deck.dwellS(photoCount: photos)
            )
        }
        return RecapTrip(route: route, stops: stops, title: "Sample", subtitle: "", endCardFigures: [])
    }

    private func frames(_ timeline: LinearTimeline) -> [Frame] {
        stride(from: 0, to: timeline.durationS, by: 1.0 / 30).map {
            Frame(time: $0, contents: timeline.overlayContents(atTime: $0))
        }
    }

    private func stamps(in frames: [Frame]) -> [(time: Double, stamp: RecapDayStamp)] {
        frames.compactMap { frame in frame.hud?.stamp.map { (frame.time, $0) } }
    }

    func testEachTurnOfTheDayIsStampedOnceAndTheFirstDayIsNot() throws {
        let config = exportConfig(dayStamp: stamp)
        let timeline = try fixedTimeline(trip(days: ["Day 1", "Day 2", "Day 3"], config: config), config)
        let stamped = stamps(in: frames(timeline))

        XCTAssertEqual(
            Set(stamped.map(\.stamp.label)), ["Day 2", "Day 3"],
            "every turn of the day is stamped; the first day is not a turn"
        )
        for day in ["Day 2", "Day 3"] {
            let times = stamped.filter { $0.stamp.label == day }.map(\.time)
            let span = try XCTUnwrap(times.last) - XCTUnwrap(times.first)
            XCTAssertLessThan(span, stamp.totalS + 0.05, "\(day) is one stamp, not two: \(span) s")
        }
    }

    func testTheStampLandsInTheHUDAsTheDaysFirstStopArrives() throws {
        let config = exportConfig(dayStamp: stamp)
        let timeline = try fixedTimeline(trip(days: ["Day 1", "Day 2", "Day 3"], config: config), config)
        let all = frames(timeline)
        for (day, index) in [("Day 2", 1), ("Day 3", 2)] {
            let times = all.filter { $0.hud?.stamp?.label == day }.map(\.time)
            let landed = try XCTUnwrap(times.last) + 1.0 / 30
            let arrival = try XCTUnwrap(timeline.holds.first { $0.stopIndex == index }).startS
            XCTAssertGreaterThanOrEqual(landed + 1e-6, arrival, "\(day) lands no earlier than its stop arrives")
            let after = try XCTUnwrap(all.first { $0.time >= landed }?.hud)
            XCTAssertNil(after.stamp, "once landed, the stamp is gone")
            XCTAssertEqual(after.day, day, "and the HUD carries the day it stamped")
            let before = try XCTUnwrap(all.last { $0.time < (times.first ?? 0) }?.hud)
            XCTAssertNotEqual(before.day, day, "before the stamp, the HUD still shows the day before")
        }
    }

    /// The pill's previous day fades out **before** the ink appears, and the new
    /// day is never in the pill while the stamp is on screen.
    func testTheDayIsNeverShownTwiceInOneFrame() throws {
        let config = exportConfig(dayStamp: stamp)
        let timeline = try fixedTimeline(trip(days: ["Day 1", "Day 2", "Day 3"], config: config), config)
        for (time, day) in stamps(in: frames(timeline)) {
            if day.clear < 1 {
                XCTAssertEqual(day.press, 0, "no ink while the previous day is still in the pill, at \(time) s")
            }
            XCTAssertNotEqual(day.label, day.previousLabel)
        }
    }

    func testTheStampIsNeverOverAPhotographOrACard() throws {
        let config = exportConfig(dayStamp: stamp)
        let timeline = try fixedTimeline(trip(days: ["Day 1", "Day 2", "Day 3"], config: config), config)
        let stamped = frames(timeline).filter { $0.hud?.stamp.map { $0.press > 0 } ?? false }
        XCTAssertFalse(stamped.isEmpty)
        for frame in stamped {
            for content in frame.contents {
                switch content {
                case .photoDeck, .journeyCard, .titleChrome, .endChrome:
                    XCTFail("the stamp shares \(frame.time) s with \(content)")
                default:
                    continue
                }
            }
        }
    }

    func testTheStampAddsNoFilmTime() throws {
        let off = exportConfig()
        let on = exportConfig(dayStamp: stamp)
        let days = ["Day 1", "Day 2", "Day 3"]
        let plain = try fixedTimeline(trip(days: days, config: off), off)
        let stamped = try fixedTimeline(trip(days: days, config: on), on)
        XCTAssertEqual(stamped.durationS, plain.durationS)
        XCTAssertEqual(stamped.holds, plain.holds, "every beat is where it was")
        XCTAssertFalse(stamped.dayStampWindows.isEmpty)
    }

    /// ADR 2026-10-26-a-one-day-film-names-no-day: a one-day film's stops carry
    /// `""`, so nothing turns and nothing is stamped. Nor is a film whose stops
    /// all fall on one named day.
    func testAOneDayFilmHasNoStamp() throws {
        let config = exportConfig(dayStamp: stamp)
        for days in [["", "", ""], ["Day 1", "Day 1", "Day 1"]] {
            let timeline = try fixedTimeline(trip(days: days, config: config), config)
            XCTAssertTrue(stamps(in: frames(timeline)).isEmpty, "\(days) stamps nothing")
        }
    }

    /// A turn with less room than `min_s` keeps the HUD's silent turn-over —
    /// it never borrows film time from anything else.
    func testATurnWithNoRoomTurnsOverUnstamped() throws {
        let tight = DayStampConfig(clearS: 0.25, pressS: 0.35, holdS: 0.9, landS: 0.55, minS: 600)
        let config = exportConfig(dayStamp: tight)
        let timeline = try fixedTimeline(trip(days: ["Day 1", "Day 2"], config: config), config)
        let all = frames(timeline)
        XCTAssertTrue(stamps(in: all).isEmpty)
        XCTAssertEqual(all.compactMap(\.hud?.day).last, "Day 2", "the HUD still turns over")
    }

    func testTheStampIsOffInHandBuiltConfigs() throws {
        let config = exportConfig()
        let timeline = try fixedTimeline(trip(days: ["Day 1", "Day 2", "Day 3"], config: config), config)
        XCTAssertTrue(timeline.dayStampWindows.isEmpty, "the films pinned before the stamp keep their frames")
    }
}
