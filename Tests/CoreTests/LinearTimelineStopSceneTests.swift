import KamomeConfig
import KamomeExportEngine
import KamomeTrackingEngine
import XCTest

/// The stop as a **coherent event in the journey** (Chiu 2026-07-26) and the
/// typed legs the trail is revealed through (PD-1) — the two things that decide
/// whether the film reads as one continuous trip or as elements scattered over a
/// map. Split from `LinearTimelineTests` to keep both files inside the budget.
final class LinearTimelineStopSceneTests: LinearTimelineTestCase {
    // MARK: - Typed legs through the reveal (PD-1)

    /// A two-leg trip: a reconstructed drive, then an inferred walk.
    private func mixedProvenanceTrip(config: TrackingConfig.Export) -> RecapTrip {
        let drive = (0...20).map { RecapCoordinate(lat: -32.0 + Double($0) * 0.01, lon: 115.75) }
        // Legs share their seam vertex, as `RecapComposer` produces them.
        let walk = (0...10).map { RecapCoordinate(lat: -31.80 + Double($0) * 0.001, lon: 115.75) }
        return RecapTrip(
            legs: [
                RecapTrip.Leg(coordinates: drive, mode: .drive, provenance: .reconstructed),
                RecapTrip.Leg(coordinates: walk, mode: .walk, provenance: .inferred)
            ],
            stops: [], title: "Mixed", subtitle: "", statsLines: [], callToAction: ""
        )
    }

    private func revealedLegs(_ contents: [OverlayContent]) -> [RecapRouteLeg] {
        for content in contents {
            if case let .routeReveal(legs) = content { return legs }
        }
        return []
    }

    /// The reveal is cut along one continuous distance axis but must reach the
    /// renderer split back into legs, each still carrying its own story — that
    /// is the whole mechanism behind the dashed inferred stroke.
    func testRevealSplitsBackIntoLegsCarryingModeAndProvenance() throws {
        let config = exportConfig()
        let timeline = try XCTUnwrap(LinearTimeline(trip: mixedProvenanceTrip(config: config), config: config))

        // Early: only the drive leg has been reached.
        let early = revealedLegs(timeline.overlayContents(atTime: config.targetDurationS * 0.2))
        XCTAssertEqual(early.count, 1)
        XCTAssertEqual(early[0].provenance, .reconstructed)
        XCTAssertEqual(early[0].mode, .drive)

        // At the end: both legs, in travel order, each keeping its own claim.
        let full = revealedLegs(timeline.overlayContents(atTime: timeline.durationS))
        XCTAssertEqual(full.map(\.provenance), [.reconstructed, .inferred])
        XCTAssertEqual(full.map(\.mode), [.drive, .walk])
    }

    /// The revealed legs must still add up to one continuous trail — no vertices
    /// dropped or duplicated by the split, and the head still lands under the
    /// vehicle.
    func testRevealedLegsStayContinuousAndEndAtTheSubject() throws {
        let config = exportConfig()
        let timeline = try XCTUnwrap(LinearTimeline(trip: mixedProvenanceTrip(config: config), config: config))

        var time = 0.5
        while time < timeline.durationS {
            let legs = revealedLegs(timeline.overlayContents(atTime: time))
            let flattened = legs.flatMap(\.coordinates)
            if let head = flattened.last {
                let subject = timeline.subjectState(atTime: time)
                XCTAssertEqual(head.lat, subject.lat, accuracy: 1e-9, "trail head must sit under the vehicle at t=\(time)")
                XCTAssertEqual(head.lon, subject.lon, accuracy: 1e-9)
            }
            // No leg is a stub, and consecutive legs meet.
            for leg in legs { XCTAssertGreaterThanOrEqual(leg.coordinates.count, 2) }
            for (previous, next) in zip(legs, legs.dropFirst()) {
                XCTAssertEqual(previous.coordinates.last?.lat ?? 0, next.coordinates.first?.lat ?? 1, accuracy: 0.02,
                               "legs must not tear apart at the seam")
            }
            time += 0.5
        }
    }

    // MARK: - The stop as an event: arrive → park → reveal → pull away

    private func firstHoldWindow(_ timeline: LinearTimeline) throws -> (start: Double, end: Double) {
        var start: Double?
        var end: Double?
        var time = 0.0
        while time <= timeline.durationS {
            let parked = timeline.subjectState(atTime: time).emphasis < 1
            if parked, start == nil { start = time }
            if let opened = start, !parked, time > opened + 0.1, end == nil { end = time }
            time += 1.0 / 30
        }
        return (try XCTUnwrap(start), try XCTUnwrap(end))
    }

    /// The whole point of the change (Chiu 2026-07-26): a stop is an event, not a
    /// visibility toggle. The car must arrive at full presence, fade out as it
    /// parks, be genuinely gone while the stop tells its story, and come back for
    /// the next leg — never blink out.
    func testCarArrivesParksStaysAwayThenPullsAwayAgain() throws {
        let config = exportConfig()
        let timeline = try XCTUnwrap(LinearTimeline(trip: sampleTrip(photoCounts: [3], config: config), config: config))
        let window = try firstHoldWindow(timeline)

        XCTAssertEqual(timeline.subjectState(atTime: window.start - 0.1).emphasis, 1, accuracy: 1e-6,
                       "the car is fully present as it arrives")

        // The fade is gradual, not a cut: sample the park ramp and require
        // intermediate values on the way down and back up.
        func presences(from: Double, to: Double) -> [Double] {
            stride(from: from, through: to, by: 1.0 / 60).map { timeline.subjectState(atTime: $0).emphasis }
        }
        let parking = presences(from: window.start, to: window.start + 0.4)
        XCTAssertTrue(parking.contains { $0 > 0.05 && $0 < 0.95 }, "the car must fade out, not cut: \(parking)")
        let leaving = presences(from: window.end - 0.4, to: window.end)
        XCTAssertTrue(leaving.contains { $0 > 0.05 && $0 < 0.95 }, "the car must fade back in, not pop: \(leaving)")

        // Genuinely away in the middle, where the stop's own content plays.
        let middle = (window.start + window.end) / 2
        XCTAssertEqual(timeline.subjectState(atTime: middle).emphasis, 0, accuracy: 1e-6)
        XCTAssertFalse(timeline.subjectState(atTime: middle).isVisible, "parked means not drawn at all")

        XCTAssertEqual(timeline.subjectState(atTime: window.end + 0.1).emphasis, 1, accuracy: 1e-6,
                       "the car is back for the next leg")
    }

    /// The hand-off: the pin fades **up** on exactly the ramp the car fades down,
    /// so the stop's identity passes from vehicle to pin in place. If the label
    /// were already solid on arrival the pin would appear beside a still-visible
    /// car; if it lagged, the map would be briefly empty.
    func testStopIdentityIsHandedFromTheCarToThePinAsItParks() throws {
        let config = exportConfig()
        let timeline = try XCTUnwrap(LinearTimeline(trip: sampleTrip(photoCounts: [3], config: config), config: config))
        let window = try firstHoldWindow(timeline)

        func labelOpacity(_ time: Double) -> Double {
            for content in timeline.overlayContents(atTime: time) {
                if case let .stopLabel(_, _, _, _, _, opacity) = content { return opacity }
            }
            return 0
        }

        // Across the park ramp the two are complementary: as the car goes, the
        // pin arrives, and their sum stays around one so the beat never blanks.
        for time in stride(from: window.start, through: window.start + 0.4, by: 1.0 / 60) {
            let presence = timeline.subjectState(atTime: time).emphasis
            let label = labelOpacity(time)
            XCTAssertEqual(presence + label, 1, accuracy: 0.02,
                           "hand-off broke at t=\(time): car \(presence), pin \(label)")
        }
    }

    /// The pin marks the same place the car stopped. They are drawn at different
    /// times, so this is what stops the scene from jumping across the map.
    func testThePinIsWhereTheCarParked() throws {
        let config = exportConfig()
        let trip = sampleTrip(photoCounts: [3], config: config)
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config))
        let window = try firstHoldWindow(timeline)

        let parkedAt = timeline.subjectState(atTime: window.start)
        var pin: RecapCoordinate?
        for content in timeline.overlayContents(atTime: (window.start + window.end) / 2) {
            if case let .photoDeck(deck) = content { pin = deck.coordinate }
        }
        let stopPoint = try XCTUnwrap(pin)
        // The car parks on the route vertex nearest the stop, so these agree to
        // within the route's own vertex spacing — not to within a car length.
        XCTAssertEqual(stopPoint.lat, parkedAt.lat, accuracy: 0.02)
        XCTAssertEqual(stopPoint.lon, parkedAt.lon, accuracy: 0.02)
    }

    /// The pull-away has to be *visible*. The photo card is opaque and sits on
    /// the stop, so if it were still drawn while the car faded back in, the car
    /// would return from behind it and the departure would never read — the scene
    /// would just cut from card to moving car. The card must be gone first.
    func testTheCardIsGoneBeforeTheCarComesBack() throws {
        let config = exportConfig()
        let trip = sampleTrip(photoCounts: [3], config: config)
        let timeline = try XCTUnwrap(LinearTimeline(trip: trip, config: config))

        func visibleDeck(_ time: Double) -> Bool {
            guard let deck = activePhotoDeck(timeline.overlayContents(atTime: time)) else { return false }
            return deck.opacity > 0.001
        }

        var lastVisibleDeck: Double?
        var carReturnStart: Double?
        var time = 0.0
        while time <= timeline.durationS {
            if visibleDeck(time) { lastVisibleDeck = time }
            let presence = timeline.subjectState(atTime: time).emphasis
            if lastVisibleDeck != nil, carReturnStart == nil, presence > 0.001 { carReturnStart = time }
            time += 1.0 / 30
        }

        let cardGone = try XCTUnwrap(lastVisibleDeck)
        let carBack = try XCTUnwrap(carReturnStart)
        XCTAssertGreaterThan(carBack, cardGone, "the car must not fade in behind a card that is still drawn")
    }

    /// A hold with nothing to show must not delete the car — that reads as a
    /// glitch, not as a stop. The route-only path (photos off) hits this.
    func testAPhotolessStopNeverParksTheCar() throws {
        let config = exportConfig()
        let timeline = try XCTUnwrap(LinearTimeline(trip: sampleTrip(photoCounts: [0], config: config), config: config))

        for time in stride(from: 0.0, through: timeline.durationS, by: 1.0 / 30) {
            XCTAssertEqual(timeline.subjectState(atTime: time).emphasis, 1, accuracy: 1e-6,
                           "the car must stay on screen through a stop that draws nothing (t=\(time))")
        }
    }
}
