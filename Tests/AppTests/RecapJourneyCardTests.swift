@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import KamomeRouteMatching
import KamomeTrackingEngine
import KamomeTripComposer
import XCTest

/// **The type-2 opening's retime, asserted rather than watched** (Chiu
/// 2026-09-02, ADR 2026-09-03).
///
/// Four decisions land in the overlay stream, and each is a rule a render can
/// only show one frame of at a time:
///
/// 1. the departure airport shows one or two photographs, not a full deck;
/// 2. the crossing carries a **Journey Card** — and only the crossing does;
/// 3. the crossing's dashed leg is put away from the landing until the end card;
/// 4. **every kilometre the film reports is the local journey.**
///
/// `miyakojima` runs through every one of them as the **type-1 control**: it must
/// be untouched, and an argument that it is untouched is not a measurement.
/// Offline throughout (`baseURL: ""` + `UnroutableSeaProvider`), the same way the
/// continuity gate runs, so this gates every CI run.
final class RecapJourneyCardTests: XCTestCase {
    private static let crossing = UnroutableSeaProvider.longHaulFixture
    private static let control = "miyakojima"

    /// Pinned, because `Locale.current` is a property of the machine and the
    /// card's second line is localized. Two desks must assert the same card.
    private static let locale = Locale(identifier: "en_US")

    /// One fixture, built the way the shipped app builds it: offline, `nil`
    /// establishing extent, content-derived pacing.
    private struct Film {
        let line: LinearTimeline
        let trip: RecapTrip
        let config: TrackingConfig.Export

        var lineAndConfig: (LinearTimeline, TrackingConfig.Export) { (line, config) }
    }

    private func film(_ fixture: String) async throws -> Film {
        let (trip, config) = try await RecapDemoFilmTests.importedRecap(
            named: fixture, baseURL: "", reconstructor: UnroutableSeaProvider.forFixture(fixture)
        )
        return Film(
            line: try XCTUnwrap(LinearTimeline(
                trip: trip, config: config, establishing: nil, locale: Self.locale
            )),
            trip: trip, config: config
        )
    }

    /// One frame that carried a pass. A named shape rather than a tuple, so the
    /// lint bar of two members is not the reason the third fact goes missing.
    private struct Shown {
        let timeS: Double
        let card: RecapJourneyCard
    }

    private func cards(in line: LinearTimeline, fps: Int) -> [Shown] {
        (0..<line.frameCount).compactMap { frame in
            let timeS = Double(frame) / Double(fps)
            for overlay in line.overlayContents(atTime: timeS) {
                if case let .journeyCard(card) = overlay { return Shown(timeS: timeS, card: card) }
            }
            return nil
        }
    }

    // MARK: - 2. The card, and only during the crossing

    func testTheJourneyCardIsOnScreenForTheCrossingBeatAndNowhereElse() async throws {
        let (line, config) = try await film(Self.crossing).lineAndConfig
        let beat = try XCTUnwrap(line.path.crossingBeatWindowsS.first, "the fixture has no crossing beat")
        let shown = cards(in: line, fps: config.fps)

        XCTAssertFalse(shown.isEmpty, "the crossing must carry a boarding pass")
        let first = try XCTUnwrap(shown.first).timeS
        let last = try XCTUnwrap(shown.last).timeS
        // Inside the beat with a frame of slack at each end — the window is
        // sampled at 1/fps, so the first and last frames land just inside it.
        XCTAssertGreaterThanOrEqual(first, beat.lowerBound - 1.0 / Double(config.fps))
        XCTAssertLessThanOrEqual(last, beat.upperBound + 1.0 / Double(config.fps))
        // ⚠️ The arc runs `zoom_transition_s` past the landing while the camera
        // closes into the destination. The pass belongs to the beat, not the arc:
        // it must be gone before the closing zoom, or it is on screen over a
        // moving camera it has nothing to do with.
        XCTAssertLessThan(
            last, beat.upperBound + config.zoomTransitionS,
            "the pass must leave with the beat, not ride the closing zoom"
        )
    }

    func testTheCardNamesBothRegionsAndCarriesTheFlightsOwnDistance() async throws {
        let made = try await film(Self.crossing)
        let (line, trip, config) = (made.line, made.trip, made.config)
        let card = try XCTUnwrap(cards(in: line, fps: config.fps).last?.card)

        // Taipei → Auckland. English over the local name, and English is what a
        // boarding pass prints (Chiu 2026-09-02).
        XCTAssertEqual(card.from.english, "TAIWAN")
        XCTAssertEqual(card.to.english, "NEW ZEALAND")
        XCTAssertEqual(RecapJourneyCard.flightNumber, "THX-9527", "the flight number is a constant")

        // The card's distance is the **flight**, and it is the one flown figure in
        // the film — see `testEveryKilometreTheFilmReportsIsTheLocalJourney`.
        //
        // 🔴 **Great circle, not `Geo.distanceM`.** The camera's distance axis is
        // equirectangular; over this fixture's Taipei → Auckland diagonal that is
        // **121 km short**, and it is where the 8,755 km quoted in
        // `Docs/handoff-type2-films.md` came from. The pass prints 8,876 km,
        // because a figure printed on a document is a claim (`CLAUDE.md` rule 5).
        func flown(_ measure: (Double, Double, Double, Double) -> Double) -> Double {
            trip.legs.filter(\.isCrossing).reduce(0.0) { total, leg in
                total + zip(leg.coordinates, leg.coordinates.dropFirst()).reduce(0.0) { run, pair in
                    run + measure(pair.0.lat, pair.0.lon, pair.1.lat, pair.1.lon)
                }
            }
        }
        let flownM = flown { Geo.greatCircleM(latA: $0, lonA: $1, latB: $2, lonB: $3) }
        XCTAssertEqual(card.distanceM, flownM, accuracy: 1)
        XCTAssertGreaterThan(card.distanceM, 8_000_000, "Taipei → Auckland is thousands of kilometres")
        XCTAssertGreaterThan(
            card.distanceM - flown { Geo.distanceM(latA: $0, lonA: $1, latB: $2, lonB: $3) }, 100_000,
            "the flat-earth measure is materially short here — that is why the card may not use it"
        )
    }

    /// The pass is the beat's own clock: it arrives, holds, and leaves, and the
    /// aircraft printed on it runs the whole arc rather than a part of it.
    func testTheCardFadesInAndOutAndItsAircraftCrossesTheWholeArc() async throws {
        let (line, config) = try await film(Self.crossing).lineAndConfig
        let shown = cards(in: line, fps: config.fps)
        let progress = shown.map(\.card.progress)
        let opacity = shown.map(\.card.opacity)

        XCTAssertEqual(try XCTUnwrap(progress.first), 0, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(progress.last), 1, accuracy: 0.02)
        XCTAssertEqual(progress, progress.sorted(), "the aircraft never flies backwards")
        XCTAssertLessThan(try XCTUnwrap(opacity.first), 0.1, "the pass arrives rather than cutting in")
        XCTAssertLessThan(try XCTUnwrap(opacity.last), 0.1, "and leaves the same way")
        XCTAssertGreaterThan(try XCTUnwrap(opacity.max()), 0.99, "it must reach full strength between them")
    }

    // MARK: - 3. The dash the crossing puts away

    func testTheCrossingsDashIsPutAwayAfterTheLandingAndDrawnAgainForTheEndCard() async throws {
        let (line, config) = try await film(Self.crossing).lineAndConfig
        let beat = try XCTUnwrap(line.path.crossingBeatWindowsS.first)

        func crossingIsDrawn(atTime timeS: Double) -> Bool {
            for overlay in line.overlayContents(atTime: timeS) {
                guard case let .routeReveal(legs) = overlay else { continue }
                // The crossing is the only `.inferred` leg whose ends straddle the
                // Pacific; length is what tells it apart from a dashed road.
                return legs.contains { leg in
                    guard let first = leg.coordinates.first, let last = leg.coordinates.last else {
                        return false
                    }
                    return Geo.distanceM(
                        latA: first.lat, lonA: first.lon, latB: last.lat, lonB: last.lon
                    ) > 1_000_000
                }
            }
            return false
        }

        XCTAssertTrue(
            crossingIsDrawn(atTime: (beat.lowerBound + beat.upperBound) / 2),
            "the dash must be drawn while the aircraft is crossing it"
        )
        let afterLanding = beat.upperBound + config.zoomTransitionS + 1
        XCTAssertFalse(
            crossingIsDrawn(atTime: afterLanding),
            "the dash must be put away once the aircraft has landed"
        )
        XCTAssertFalse(
            crossingIsDrawn(atTime: line.durationS - config.endCardS - 0.5),
            "and stay away for the whole of the destination's local trip"
        )
        XCTAssertTrue(
            crossingIsDrawn(atTime: line.durationS - 0.1),
            "the end card shows the whole journey, so the dash returns for it"
        )
    }

    // MARK: - 4. Every kilometre in the film is the local journey

    func testEveryKilometreTheFilmReportsIsTheLocalJourney() async throws {
        let made = try await film(Self.crossing)
        let (line, trip, config) = (made.line, made.trip, made.config)
        let flownM = try XCTUnwrap(cards(in: line, fps: config.fps).last?.card.distanceM)

        func flown(_ measure: (Double, Double, Double, Double) -> Double) -> Double {
            trip.legs.filter(\.isCrossing).reduce(0.0) { total, leg in
                total + zip(leg.coordinates, leg.coordinates.dropFirst()).reduce(0.0) { run, pair in
                    run + measure(pair.0.lat, pair.0.lon, pair.1.lat, pair.1.lon)
                }
            }
        }

        func odometer(atTime timeS: Double) -> Double? {
            for overlay in line.overlayContents(atTime: timeS) {
                if case let .hud(_, _, travelledM) = overlay { return travelledM }
            }
            return nil
        }
        let beat = try XCTUnwrap(line.path.crossingBeatWindowsS.first)
        // The HUD is suppressed under the title card, so read it after that.
        let beforeFlying = try XCTUnwrap(odometer(atTime: max(beat.lowerBound - 0.1, config.titleCardS)))
        let landed = try XCTUnwrap(odometer(atTime: beat.upperBound + 0.1))
        let ending = try XCTUnwrap(odometer(atTime: line.durationS - config.endCardS - 0.1))

        // The whole point: 8,755 km of flight never enters the readout, so the
        // odometer holds still across the crossing instead of counting it.
        XCTAssertLessThan(beforeFlying, 1_000, "the film has not driven anywhere before it takes off")
        XCTAssertEqual(landed, beforeFlying, accuracy: 1, "the odometer holds while the aircraft is up")
        XCTAssertLessThan(
            ending, flownM / 10,
            "the end of the film must read the local journey, not 97% flight"
        )
        // **The two cards subtract on the ruler their own total was built with.**
        // 🔴 The subtlety that cost a measurement on 2026-09-03: `TripStats`
        // sums `Geo.distanceM`, the equirectangular one, so the flight has to come
        // off it the same way. Subtracting the *pass's* great-circle figure
        // instead — which is 121 km longer over this diagonal, and is the right
        // number to print — puts 148 km on both cards where the journey is 269.
        // Same flight, two rulers, each where it is correct.
        let stats = TripStats(
            distanceM: flown { Geo.distanceM(latA: $0, lonA: $1, latB: $2, lonB: $3) } + 269_000,
            driveS: 0, walkS: 0, stopCount: 0, topSpeedKmh: 0
        )
        let localM = try XCTUnwrap(RecapComposer.localDistanceM(stats: stats, legs: trip.legs))
        XCTAssertEqual(
            localM, 269_000, accuracy: 1,
            "the cards must report the local journey, not a figure two rulers wide of it"
        )
    }

    // MARK: - 1. The departure airport, and the type-1 control

    func testTheDepartureAirportShowsAtMostTheConfiguredPhotographs() async throws {
        let made = try await film(Self.crossing)
        let (trip, config) = (made.trip, made.config)
        let trimmed = RecapTypeTwoFilm.trimmedToTheDestination(trip, config: config)
        let departure = try XCTUnwrap(trimmed.stops.first)

        XCTAssertLessThanOrEqual(departure.photos.count, config.departureStopMaxPhotos)
        // The dwell is repriced with the deck, not left at the old count's value.
        XCTAssertEqual(
            departure.dwellS,
            LinearTimeline.deck(config: config).dwellS(photoCount: departure.photos.count),
            accuracy: 0.001,
            "a capped stop whose dwell still prices the photographs it no longer shows is a value lying"
        )
        // Only the departure is capped: the destination's own stops are untouched.
        XCTAssertTrue(
            trimmed.stops.dropFirst().contains { $0.photos.count > config.departureStopMaxPhotos },
            "the cap is an instruction about the airport, not a trip-wide photo limit"
        )
    }

    /// **The type-1 control, measured** (`Docs/handoff-type2-opening-retime.md`).
    ///
    /// Not "type-1 is unaffected because the code is gated" — that is an argument.
    /// This asserts the three things the retime could have leaked into a local
    /// film: a boarding pass, a hidden leg, and a changed odometer.
    func testTheTypeOneControlDrawsNoCardHidesNoLegAndCountsEveryKilometre() async throws {
        let made = try await film(Self.control)
        let (line, trip, config) = (made.line, made.trip, made.config)
        XCTAssertFalse(line.opensOnTheFlight, "the control must not be a type-2 film")
        XCTAssertTrue(trip.legs.allSatisfy { !$0.isCrossing }, "the control has no crossing")
        XCTAssertTrue(cards(in: line, fps: config.fps).isEmpty, "a local film has no boarding pass")

        // Every leg is drawn for the whole film, and the odometer is the whole
        // route — with no crossing, local distance and route distance are the
        // same number at every instant, which is what "unchanged" means here.
        for frame in stride(from: 0, to: line.frameCount, by: config.fps) {
            let timeS = Double(frame) / Double(config.fps)
            XCTAssertEqual(
                line.path.traveledLocalDistanceM(atTime: timeS),
                line.path.traveledDistanceM(atTime: timeS),
                accuracy: 0.001,
                "the control's odometer must be untouched at \(timeS)s"
            )
        }
    }
}
