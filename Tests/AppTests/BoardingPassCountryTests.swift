@testable import Kamome
@testable import KamomeExportEngine
import KamomePersistence
import KamomeRouteMatching
import XCTest

/// **The boarding pass names a flight's two ends by the country Apple named
/// the stops beside it** (ADR file 2026-10-03) — not by `CountryExtent`'s six
/// rows, which left a flight to Vietnam with a plane and no pass.
///
/// Every place here is a public airport or an arbitrary point at sea, never a
/// real journey (`CLAUDE.md` §0).
final class BoardingPassCountryTests: XCTestCase {
    private let start = 1_790_000_000.0
    private let taoyuanAirport = (25.08, 121.23)
    private let atSea = (21.0, 118.0)
    private let daNangAirport = (16.04, 108.20)
    private let hoiAn = (15.88, 108.33)

    private func stop(_ id: String, _ place: (Double, Double), at offsetS: Double, country: String?) -> StopRecord {
        StopRecord(
            id: id, tripId: "trip", lat: place.0, lon: place.1,
            arrivedAt: start + offsetS, departedAt: start + offsetS + 600, countryCode: country
        )
    }

    private func flight(leavingAt offsetS: Double) -> SegmentRecord {
        SegmentRecord(
            id: "flight", tripId: "trip", mode: "drive", startedAt: start + offsetS,
            endedAt: start + offsetS + 10_800, matchedPolyline: nil, source: "exif",
            routability: SegmentRoutability.noRoad.rawValue
        )
    }

    // MARK: - Which stop names each end

    /// The stops either side of the flight, by time. A photograph from the
    /// aircraft makes a stop at sea, where Apple names no country (""), and a
    /// stop never named (nil) says nothing either: the flight still left from the
    /// country before them.
    func testEachEndIsTheNearestStopWithACountryAndTheSeaIsSkipped() {
        let stops = [
            stop("home", taoyuanAirport, at: 0, country: "TW"),
            stop("sea", atSea, at: 3_000, country: ""),
            stop("unnamed", atSea, at: 3_300, country: nil),
            stop("landing", daNangAirport, at: 15_000, country: "VN"),
            stop("town", hoiAn, at: 30_000, country: "VN")
        ]
        let ends = RecapComposer.crossingCountryCodes(flight(leavingAt: 3_600), stops: stops.reversed())
        XCTAssertEqual(ends.origin, "TW")
        XCTAssertEqual(ends.destination, "VN")
    }

    func testAnEndWithNoCountryAnywhereIsNil() {
        let stops = [
            stop("sea", atSea, at: 3_000, country: ""),
            stop("landing", daNangAirport, at: 15_000, country: "VN")
        ]
        let ends = RecapComposer.crossingCountryCodes(flight(leavingAt: 3_600), stops: stops)
        XCTAssertNil(ends.origin, "nothing before the flight names a country, so nothing may be printed")
        XCTAssertEqual(ends.destination, "VN")
    }

    /// Only a crossing carries countries; a road leg never prints a pass.
    func testOnlyACrossingLegCarriesCountries() {
        let stops = [
            stop("home", taoyuanAirport, at: 0, country: "TW"),
            stop("landing", daNangAirport, at: 15_000, country: "VN")
        ]
        let points = [taoyuanAirport, daNangAirport].enumerated().map { index, place in
            TrackpointRecord(segmentId: "flight", ts: start + Double(index), lat: place.0, lon: place.1)
        }
        var road = flight(leavingAt: 3_600)
        road.routability = SegmentRoutability.road.rawValue
        let legs = RecapComposer.legs(
            from: [(flight(leavingAt: 3_600), points), (road, points)], epsilonM: 15, matchedEpsilonM: 5,
            stops: stops
        )
        XCTAssertEqual(legs.count, 2)
        XCTAssertTrue(legs[0].isCrossing)
        XCTAssertEqual(legs[0].countryCodes.origin, "TW")
        XCTAssertEqual(legs[0].countryCodes.destination, "VN")
        XCTAssertFalse(legs[1].isCrossing)
        XCTAssertNil(legs[1].countryCodes.origin)
        XCTAssertNil(legs[1].countryCodes.destination)
    }

    // MARK: - What the pass prints

    private func trip(origin: String?, destination: String?) -> RecapTrip {
        let coordinates = [taoyuanAirport, daNangAirport].map { RecapCoordinate(lat: $0.0, lon: $0.1) }
        return RecapTrip(
            legs: [RecapTrip.Leg(
                coordinates: coordinates, mode: .drive, provenance: .inferred, isCrossing: true,
                countryCodes: (origin, destination)
            )],
            stops: [], title: "", subtitle: "", endCardFigures: []
        )
    }

    /// Vietnam has no `CountryExtent` row, and is on the pass anyway: the name
    /// comes from the stop's code, worded by the system in both languages.
    func testACountryOutsideTheExtentTableIsOnThePass() throws {
        XCTAssertNil(CountryExtent.containing(lat: daNangAirport.0, lon: daNangAirport.1),
                     "the point of this test is a country the table does not have")
        let card = try XCTUnwrap(LinearTimeline.journeyCard(
            trip: trip(origin: "TW", destination: "VN"), locale: Locale(identifier: "zh_Hant_TW")
        ))
        XCTAssertEqual(card.from.english, "TAIWAN")
        XCTAssertEqual(card.to.english, "VIETNAM")
        XCTAssertEqual(card.to.local, "越南")
    }

    /// An end with no country draws no pass — never a blank FROM.
    func testAnEndWithNoCountryDrawsNoPass() {
        let english = Locale(identifier: "en_US")
        XCTAssertNil(LinearTimeline.journeyCard(trip: trip(origin: nil, destination: "VN"), locale: english))
        XCTAssertNil(LinearTimeline.journeyCard(trip: trip(origin: "TW", destination: ""), locale: english))
    }
}
