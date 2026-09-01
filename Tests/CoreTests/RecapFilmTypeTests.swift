import KamomeExportEngine
import XCTest

/// **Which of the three films a trip is** (`RecapFilmType`, Chiu 2026-09-01).
///
/// The two counter-examples in this file are the whole reason the rule counts
/// *local journeys* rather than the two things it is tempting to count. Both are
/// real trips, and each breaks one of the obvious rules:
///
/// - a **round trip** — Taiwan → Japan → Taiwan — is two crossings and one
///   destination, so counting crossings is wrong;
/// - a **domestic flight** — Tokyo → Miyakojima — is one country and is still a
///   journey to a destination, so counting countries is wrong.
///
/// Both are asserted below. If either ever flips, the rule has been replaced by
/// one of the two it was chosen over.
final class RecapFilmTypeTests: XCTestCase {
    private func leg(_ coordinates: [(Double, Double)], crossing: Bool = false) -> RecapTrip.Leg {
        RecapTrip.Leg(
            coordinates: coordinates.map { RecapCoordinate(lat: $0.0, lon: $0.1) },
            mode: .drive,
            provenance: crossing ? .inferred : .reconstructed,
            isCrossing: crossing
        )
    }

    /// Plausible coordinates of public places, never a real trip (`CLAUDE.md` §0).
    private let taipei = [(25.03, 121.56), (25.08, 121.23)]
    private let ishigaki = [(24.34, 124.16), (24.45, 124.15)]
    private let tokyo = [(35.68, 139.65), (35.55, 139.78)]
    private let miyakojima = [(24.79, 125.28), (24.73, 125.32)]

    // MARK: - The three types

    func testOneLocalJourneyIsTheLocalFilm() {
        let trip = [leg(taipei)]
        XCTAssertEqual(RecapFilmType.distinctJourneyCount(legs: trip), 1)
        XCTAssertEqual(RecapFilmType.classify(legs: trip, everyLegEstablished: true), .local)
    }

    func testHomeThenOneDestinationAbroadIsTheSecondFilm() {
        let trip = [leg(taipei), leg([taipei[1], ishigaki[0]], crossing: true), leg(ishigaki)]
        XCTAssertEqual(RecapFilmType.distinctJourneyCount(legs: trip), 2)
        XCTAssertEqual(RecapFilmType.classify(legs: trip, everyLegEstablished: true), .oneDestination)
    }

    func testThreeDistinctRegionsIsTheMultiRegionFilm() {
        let trip = [
            leg(taipei),
            leg([taipei[1], tokyo[0]], crossing: true), leg(tokyo),
            leg([tokyo[1], ishigaki[0]], crossing: true), leg(ishigaki)
        ]
        XCTAssertEqual(RecapFilmType.distinctJourneyCount(legs: trip), 3)
        XCTAssertEqual(RecapFilmType.classify(legs: trip, everyLegEstablished: true), .multiRegion)
    }

    // MARK: - The two counter-examples the rule exists for

    /// **Counting crossings would call this a multi-region trip.** It is two
    /// crossings, three runs of road, and *one* destination — the return lands on
    /// ground the first journey already covered, so it folds.
    func testARoundTripIsOneDestinationAndNotThreeRegions() {
        let trip = [
            leg(taipei),
            leg([taipei[1], ishigaki[0]], crossing: true),
            leg(ishigaki),
            leg([ishigaki[1], taipei[1]], crossing: true),
            leg(taipei.reversed().map { $0 })
        ]
        XCTAssertEqual(
            RecapFilmType.distinctJourneyCount(legs: trip), 2,
            "the flight home returns to a region already visited and must fold"
        )
        XCTAssertEqual(
            RecapFilmType.classify(legs: trip, everyLegEstablished: true), .oneDestination,
            "two crossings, one destination — counting crossings is what this rule rejects"
        )
    }

    /// **Counting countries would call this a local trip.** Tokyo → Miyakojima
    /// never leaves Japan and is still a journey to a destination — which is why
    /// `CountryExtent` may name a region but must never be its identity.
    func testADomesticFlightIsStillAJourneyToADestination() {
        let trip = [leg(tokyo), leg([tokyo[1], miyakojima[0]], crossing: true), leg(miyakojima)]
        XCTAssertEqual(
            RecapFilmType.classify(legs: trip, everyLegEstablished: true), .oneDestination,
            "one country, two local journeys — counting countries is what this rule rejects"
        )
    }

    // MARK: - Unknown is a state, not a default

    func testALegNobodyRoutedMakesTheTripUnclassifiable() {
        let trip = [leg(taipei), leg([taipei[1], ishigaki[0]], crossing: true), leg(ishigaki)]
        XCTAssertEqual(
            RecapFilmType.classify(legs: trip, everyLegEstablished: false), .unknown,
            "an unrouted leg may be hiding a crossing, and 'we never found out' is not 'local'"
        )
    }

    /// Unknown must be *distinguishable* from local while *rendering* as local.
    /// Collapsing the two is exactly what `SegmentRoutability` refuses one level
    /// down, and for the same reason: a caller can tell the user the film will
    /// improve, which a silent `.local` cannot.
    func testUnknownRendersTheLocalFilmWithoutBeingIt() {
        XCTAssertEqual(RecapFilmType.unknown.renderedForm, .local)
        XCTAssertNotEqual(RecapFilmType.unknown, RecapFilmType.local)
        XCTAssertFalse(RecapFilmType.unknown.hasDestinationAbroad)
        XCTAssertTrue(RecapFilmType.oneDestination.hasDestinationAbroad)
    }

    /// A trip that opens on a crossing (`Docs/camera-arcs.md` §4 Case C) has an
    /// empty run before it, which must not count as a journey.
    func testATripThatBeginsWithACrossingHasOneJourneyNotTwo() {
        let trip = [leg([taipei[1], ishigaki[0]], crossing: true), leg(ishigaki)]
        XCTAssertEqual(RecapFilmType.distinctJourneyCount(legs: trip), 1)
        XCTAssertEqual(RecapFilmType.classify(legs: trip, everyLegEstablished: true), .local)
    }

    /// The default on `RecapTrip` must be the honest one: a synthetic trip that
    /// was never routed is unknown, and renders exactly what it renders today.
    func testASyntheticTripDefaultsToUnknownRatherThanLocal() {
        let trip = RecapTrip(
            route: [RecapCoordinate(lat: 25.03, lon: 121.56), RecapCoordinate(lat: 25.08, lon: 121.23)],
            stops: [], title: "t", subtitle: "s", statsLines: [], callToAction: "c"
        )
        XCTAssertEqual(trip.filmType, .unknown)
        XCTAssertEqual(trip.filmType.renderedForm, .local)
    }
}
