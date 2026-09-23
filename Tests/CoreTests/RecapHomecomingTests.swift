import KamomeConfig
import KamomeExportEngine
import XCTest

/// **The film ends at the destination** (ADR 2026-09-01, built 2026-09-23):
/// `RecapTypeTwoFilm.homecomingLegIndex` finds where the trip starts home.
///
/// Every trip here is built from the coordinates of public places — airports and
/// city centres — never from a real journey (`CLAUDE.md` §0).
final class RecapHomecomingTests: XCTestCase {
    private func leg(_ coordinates: [(Double, Double)], crossing: Bool = false) -> RecapTrip.Leg {
        RecapTrip.Leg(
            coordinates: coordinates.map { RecapCoordinate(lat: $0.0, lon: $0.1) },
            mode: .drive,
            provenance: crossing ? .inferred : .reconstructed,
            isCrossing: crossing
        )
    }

    /// `discovery.away_radius_m` as shipped — asserted against the config below.
    private let homeRadiusM = 40_000.0

    private let taipeiCity = (25.03, 121.56)
    private let taoyuanAirport = (25.08, 121.23)
    private let songshanAirport = (25.07, 121.55)
    private let kaohsiungAirport = (22.58, 120.35)
    private let nahaAirport = (26.21, 127.65)
    private let miyakoAirport = (24.78, 125.30)
    private let miyakoTown = (24.80, 125.28)
    private let miyakoBeach = (24.73, 125.33)
    private let ishigakiAirport = (24.40, 124.25)
    private let ishigakiTown = (24.34, 124.16)

    func testTheRadiusIsTheShippedDefinitionOfAway() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Config/TrackingConfig.json")
        XCTAssertEqual(try TrackingConfigLoader.load(contentsOf: url).discovery.awayRadiusM, homeRadiusM)
    }

    func testAOneWayTripNeverComesHome() {
        let trip = [
            leg([taipeiCity, taoyuanAirport]),
            leg([taoyuanAirport, miyakoAirport], crossing: true),
            leg([miyakoAirport, miyakoTown])
        ]
        XCTAssertNil(RecapTypeTwoFilm.homecomingLegIndex(legs: trip, homeRadiusM: homeRadiusM))
    }

    func testTheFlightHomeIsWhereTheFilmEnds() {
        let trip = [
            leg([taoyuanAirport, miyakoAirport], crossing: true),
            leg([miyakoAirport, miyakoTown, miyakoAirport]),
            leg([miyakoAirport, taoyuanAirport], crossing: true),
            leg([taoyuanAirport, taipeiCity])
        ]
        XCTAssertEqual(RecapTypeTwoFilm.homecomingLegIndex(legs: trip, homeRadiusM: homeRadiusM), 2)
    }

    /// A transit with nothing but an airport photograph (Miyakojima → Naha →
    /// Taoyuan) is part of the way home, so the homecoming starts at its first
    /// leg — but never reaches back into the outbound crossing.
    func testATransitOnTheWayHomeIsPartOfTheWayHome() {
        let trip = [
            leg([taoyuanAirport, nahaAirport], crossing: true),
            leg([nahaAirport, miyakoAirport], crossing: true),
            leg([miyakoAirport, miyakoTown, miyakoAirport]),
            leg([miyakoAirport, nahaAirport], crossing: true),
            leg([nahaAirport, taoyuanAirport], crossing: true)
        ]
        XCTAssertEqual(RecapTypeTwoFilm.homecomingLegIndex(legs: trip, homeRadiusM: homeRadiusM), 3)
    }

    func testAFlightStraightBackIsNotWalkedIntoTheOutboundCrossing() {
        let trip = [
            leg([taoyuanAirport, miyakoAirport], crossing: true),
            leg([miyakoAirport, taoyuanAirport], crossing: true)
        ]
        XCTAssertEqual(RecapTypeTwoFilm.homecomingLegIndex(legs: trip, homeRadiusM: homeRadiusM), 1)
    }

    /// **The case a scale-free rule gets wrong.** Ishigaki is nearer Taipei than
    /// Naha is, so "nearer home than the destination" would have ended this film
    /// at the transit. It is 270 km from home, which is away.
    func testAnOutboundTransitIsNotMistakenForHome() {
        let trip = [
            leg([taipeiCity, taoyuanAirport]),
            leg([taoyuanAirport, nahaAirport], crossing: true),
            leg([nahaAirport, ishigakiAirport], crossing: true),
            leg([ishigakiAirport, ishigakiTown])
        ]
        XCTAssertNil(RecapTypeTwoFilm.homecomingLegIndex(legs: trip, homeRadiusM: homeRadiusM))
    }

    func testLandingAtTheOtherAirportOfTheSameCityIsHome() {
        let trip = [
            leg([taoyuanAirport, miyakoAirport], crossing: true),
            leg([miyakoAirport, miyakoTown]),
            leg([miyakoTown, songshanAirport], crossing: true)
        ]
        XCTAssertEqual(RecapTypeTwoFilm.homecomingLegIndex(legs: trip, homeRadiusM: homeRadiusM), 2)
    }

    /// Documented, not hidden: a different city is not home by this rule, and
    /// that film keeps its last flight.
    func testFlyingHomeToADifferentCityKeepsTheFlight() {
        let trip = [
            leg([taoyuanAirport, miyakoAirport], crossing: true),
            leg([miyakoAirport, miyakoTown]),
            leg([miyakoTown, kaohsiungAirport], crossing: true)
        ]
        XCTAssertNil(RecapTypeTwoFilm.homecomingLegIndex(legs: trip, homeRadiusM: homeRadiusM))
    }

    /// A beach photograph at the destination is a "no road" leg too. It lands
    /// away, so it is never the way home.
    func testANoRoadBeachAtTheDestinationIsNotTheWayHome() {
        let trip = [
            leg([taoyuanAirport, miyakoAirport], crossing: true),
            leg([miyakoAirport, miyakoTown]),
            leg([miyakoTown, miyakoBeach], crossing: true),
            leg([miyakoBeach, miyakoAirport], crossing: true),
            leg([miyakoAirport, taoyuanAirport], crossing: true)
        ]
        XCTAssertEqual(
            RecapTypeTwoFilm.homecomingLegIndex(legs: trip, homeRadiusM: homeRadiusM), 4,
            "the beach legs are away; only the flight that lands home is the homecoming"
        )
    }

    func testATripWithNoCrossingNeverComesHome() {
        XCTAssertNil(RecapTypeTwoFilm.homecomingLegIndex(
            legs: [leg([taipeiCity, taoyuanAirport, taipeiCity])], homeRadiusM: homeRadiusM
        ))
    }
}
