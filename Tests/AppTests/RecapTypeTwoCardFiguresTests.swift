@testable import Kamome
import KamomeConfig
@testable import KamomeExportEngine
import XCTest

/// **What a type-2 film says about itself in words and figures** (Chiu
/// 2026-09-05, ADR 2026-09-05 (c)).
///
/// Two rules that are easy to state and were both broken in the same way — by a
/// second implementation quietly disagreeing with the first:
///
/// 1. the departure airport is named by the country mark over it, so its own
///    name never prints on **any** surface;
/// 2. the closing card's kilometres are the odometer's, so a viewer who watched
///    the HUD reach a number is shown that number.
///
/// Its own class rather than more of `RecapJourneyCardTests`, which is at its
/// type-body budget; the film both build comes from `TypeTwoFilm`.
final class RecapTypeTwoCardFiguresTests: XCTestCase {
    /// 🔴 **The departure airport's name appears nowhere in the film** (Chiu
    /// 2026-09-05, ADR 2026-09-05 (c)) — the intended consequence of the country name
    /// winning at a place that has two.
    ///
    /// Asserted across **every surface that can print a stop's name**, not only
    /// the map label: the pin's label, the photo card under it, and the HUD's
    /// place. The rule is one line in `LinearTimeline.displayName(of:)` precisely
    /// so it cannot be honoured in two of the three and forgotten in the third,
    /// and this is what would catch that.
    func testTheDepartureAirportIsNeverNamedInTheFilm() async throws {
        let made = try await TypeTwoFilm.make()
        let (line, trip, config) = (made.line, made.trip, made.config)
        let departure = try XCTUnwrap(
            RecapTypeTwoFilm.trimmedToTheDestination(trip, config: config).stops.first
        )

        let printed = namesPrinted(in: line, fps: config.fps, departure: departure.coordinate)
        XCTAssertTrue(printed.atDeparture.isEmpty, "the departure airport printed \(printed.atDeparture)")
        // ...and the rest of the journey is named as it always was, so this is a
        // rule about one stop rather than a film that lost its labels.
        XCTAssertFalse(printed.elsewhere.isEmpty, "every other stop must still print its name")

        // The HUD names where the vehicle is parked, and it is the third surface
        // the rule has to reach.
        for frame in 0..<line.frameCount {
            let timeS = Double(frame) / Double(config.fps)
            guard line.holdingStopIndex(atTime: timeS) == 0 else { continue }
            for case let .hud(_, place, _) in line.overlayContents(atTime: timeS) {
                XCTAssertNil(place, "the HUD named the departure airport at \(timeS)s")
            }
        }
        XCTAssertNil(line.displayName(of: 0), "the rule is the departure stop's, stated once")
        XCTAssertNotNil(line.displayName(of: 1), "and it reaches no other stop")
    }

    /// Every stop name the film draws on the map, split by whether it belongs to
    /// the departure's own point.
    ///
    /// ⚠️ **Identified by coordinate, never by name.** CI runs with no geocoder,
    /// so every stop carries the same `stop_unnamed` fallback and a string
    /// comparison would fail on stops this rule has nothing to do with.
    private func namesPrinted(
        in line: LinearTimeline, fps: Int, departure: RecapCoordinate
    ) -> (atDeparture: [String], elsewhere: [String]) {
        var atDeparture: [String] = []
        var elsewhere: [String] = []
        func note(_ name: String?, at coordinate: RecapCoordinate) {
            guard let name else { return }
            if coordinate == departure { atDeparture.append(name) } else { elsewhere.append(name) }
        }
        for frame in 0..<line.frameCount {
            for overlay in line.overlayContents(atTime: Double(frame) / Double(fps)) {
                switch overlay {
                case let .stopLabel(name, coordinate, _, opacity):
                    if opacity > 0.01 { note(name, at: coordinate) }
                case let .photoDeck(deck):
                    if deck.opacity > 0.01 { note(deck.name, at: deck.coordinate) }
                default: break
                }
            }
        }
        return (atDeparture, elsewhere)
    }

    /// 🔴 **The closing card's kilometres are the odometer's** (ADR 2026-09-05 (c)).
    ///
    /// `RecapTrip.localRouteDistanceM` (what the card prints, measured off the
    /// legs) and `CameraPath.traveledLocalDistanceM` (what the HUD counts up to,
    /// measured off the path's totals) are two implementations of one quantity.
    /// Nothing but this would catch them drifting, and a film whose odometer
    /// reaches one number while its closing card claims another is the exact
    /// defect the 2026-09-02 rule was written for.
    func testTheClosingCardsDistanceIsTheOdometersOwn() async throws {
        let made = try await TypeTwoFilm.make()
        let (line, trip, config) = (made.line, made.trip, made.config)
        let journey = try XCTUnwrap(
            RecapTypeTwoFilm.destinationJourney(legs: trip.legs, stops: trip.stops, config: config)
        )
        let card = RecapTrip.localRouteDistanceM(legs: journey.legs)
        let odometer = line.path.traveledLocalDistanceM(atTime: line.durationS - config.endCardS)

        XCTAssertEqual(card, odometer, accuracy: max(odometer * 0.001, 1))
        XCTAssertGreaterThan(card, 0, "a type-2 film that drove nowhere would make the card meaningless")
        // And the flight is not in it: the whole route is an order of magnitude
        // longer, and that difference is the crossing.
        XCTAssertLessThan(
            card, RecapTrip.localRouteDistanceM(legs: trip.legs.map {
                RecapTrip.Leg(coordinates: $0.coordinates, mode: $0.mode, provenance: $0.provenance)
            }),
            "the crossing must not reach the card"
        )
    }
}
