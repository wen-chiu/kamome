import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// The persistent HUD's *content* over the whole film (Chiu 2026-07-31): which
/// day it is, where we are when we are somewhere, and how far the journey has
/// come. Drawing is `RecapOverlayRendererTests`' business; this pins down what the
/// timeline says at each instant, which is where the behaviour actually lives.
final class LinearTimelineHUDTests: LinearTimelineTestCase {
    private struct HUD: Equatable {
        let time: Double
        let dayLabel: String
        let place: String?
        let travelledM: Double
    }

    /// A three-day trip, so the day counter has something to roll over.
    private func multiDayTrip(config: TrackingConfig.Export) -> RecapTrip {
        let route = (0...40).map { RecapCoordinate(lat: -32.0 + Double($0) * 0.01, lon: 115.75) }
        let deck = RecapDeck(
            photoHoldS: config.deckPhotoHoldS, zoomS: config.deckZoomS,
            labelLeadS: config.deckLabelLeadS, photoMinHoldS: config.deckPhotoMinHoldS
        )
        let stops = (0..<3).map { index -> RecapTrip.Stop in
            RecapTrip.Stop(
                coordinate: route[(index + 1) * 9],
                name: "Stop \(index + 1)", dayLabel: "Day \(index + 1)", detail: nil,
                photos: (0..<3).map { .asset("s\(index)-\($0)") },
                dwellS: deck.dwellS(photoCount: 3)
            )
        }
        return RecapTrip(
            route: route, stops: stops, title: "Sample", subtitle: "3 stops",
            statsLines: ["291 km · 3 stops"], callToAction: "Get this route"
        )
    }

    private func sample(_ timeline: LinearTimeline, dt: Double = 1.0 / 30) -> [HUD] {
        var samples: [HUD] = []
        var time = 0.0
        while time <= timeline.durationS {
            for content in timeline.overlayContents(atTime: time) {
                if case let .hud(dayLabel, place, travelledM) = content {
                    samples.append(HUD(time: time, dayLabel: dayLabel, place: place, travelledM: travelledM))
                }
            }
            time += dt
        }
        return samples
    }

    /// The point of moving these numbers off the photo card: they are on screen
    /// **between** stops too. Before, a viewer scrubbing to the middle of a leg saw
    /// no day and no distance at all.
    func testHUDIsOnScreenWhileTravellingNotOnlyAtStops() throws {
        let config = exportConfig()
        let timeline = try XCTUnwrap(LinearTimeline(trip: multiDayTrip(config: config), config: config))
        let samples = sample(timeline)

        XCTAssertFalse(samples.isEmpty, "the HUD must draw at all")
        let travelling = samples.filter { $0.place == nil }
        let parked = samples.filter { $0.place != nil }
        XCTAssertFalse(travelling.isEmpty, "the HUD must be on screen mid-leg, with no stop in the frame")
        XCTAssertFalse(parked.isEmpty, "and it must name the stop while parked at one")
        XCTAssertEqual(
            Set(parked.compactMap(\.place)), ["Stop 1", "Stop 2", "Stop 3"],
            "every stop names itself while the film is parked at it"
        )
    }

    /// The distance is a running total for the whole journey, not a per-stop
    /// figure — it only ever climbs, and it climbs *while the car moves* rather
    /// than jumping at each stop.
    func testDistanceIsARunningTotalThatOnlyClimbs() throws {
        let config = exportConfig()
        let timeline = try XCTUnwrap(LinearTimeline(trip: multiDayTrip(config: config), config: config))
        let samples = sample(timeline)

        for (previous, next) in zip(samples, samples.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                next.travelledM, previous.travelledM - 0.5,
                "the running total went backwards at t=\(next.time)"
            )
        }
        let first = try XCTUnwrap(samples.first), last = try XCTUnwrap(samples.last)
        XCTAssertGreaterThan(last.travelledM, first.travelledM, "the total must actually grow across the film")

        // It climbs on the road, not only in the jump between stops: the leg
        // between the first two stops has to contain distinct readings.
        let onFirstLeg = samples.filter { $0.place == nil && $0.travelledM > 0 }.prefix(60)
        XCTAssertGreaterThan(
            Set(onFirstLeg.map { Int($0.travelledM / 100) }).count, 1,
            "the readout must move while the car is moving"
        )
    }

    /// The day is the day of the stop most recently reached, held across the leg
    /// that follows it — a leg belongs to no stop, so it inherits from the one
    /// just left rather than from the one not yet arrived at.
    func testDayHoldsFromTheStopJustLeftUntilTheNextIsReached() throws {
        let config = exportConfig()
        let timeline = try XCTUnwrap(LinearTimeline(trip: multiDayTrip(config: config), config: config))
        let samples = sample(timeline)

        XCTAssertEqual(try XCTUnwrap(samples.first).dayLabel, "Day 1", "the film opens on the trip's first day")
        XCTAssertEqual(try XCTUnwrap(samples.last).dayLabel, "Day 3", "and ends on its last")
        // Never runs backwards, and never skips ahead of the stop it belongs to.
        let order = ["Day 1": 0, "Day 2": 1, "Day 3": 2]
        for (previous, next) in zip(samples, samples.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                order[next.dayLabel] ?? -1, order[previous.dayLabel] ?? -1,
                "the day counter went backwards at t=\(next.time)"
            )
        }
        for parked in samples where parked.place != nil {
            let expected = "Day " + String(try XCTUnwrap(parked.place).suffix(1))
            XCTAssertEqual(parked.dayLabel, expected, "at \(parked.place ?? "") the HUD must show that stop's day")
        }
    }

    /// The title and end cards are full-bleed and own their seconds — chrome over
    /// a centred title stack is clutter, and the distance there reads "0 km".
    func testHUDStandsDownUnderTheTitleAndEndCards() throws {
        let config = exportConfig()
        let timeline = try XCTUnwrap(LinearTimeline(trip: multiDayTrip(config: config), config: config))
        let samples = sample(timeline)
        let times = samples.map(\.time)

        for content in timeline.overlayContents(atTime: 0) {
            if case .hud = content { XCTFail("the HUD must not draw over the title card") }
        }
        XCTAssertGreaterThan(try XCTUnwrap(times.first), 0, "the HUD waits for the title card to clear")
        XCTAssertLessThan(
            try XCTUnwrap(times.last), timeline.durationS - 1,
            "and stands down again before the end card"
        )
    }
}
