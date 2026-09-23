@testable import Kamome
import KamomeExportEngine
import KamomePersistence
import KamomeRouteMatching
import XCTest

/// **The records a film is made from end at the destination**
/// (`RecapComposer.filmRecords`, ADR 2026-09-01, built 2026-09-23).
///
/// The rule is `RecapTypeTwoFilm.homecomingLegIndex` (`RecapHomecomingTests`);
/// this is its application to stored records, which is cut **by time** — the one
/// thing a round trip cannot confuse, because it returns to the place it left.
///
/// Public airport and town coordinates only, never a real trip (`CLAUDE.md` §0).
final class RecapFilmRecordsTests: XCTestCase {
    private let day = 86_400.0
    private let start = 1_771_000_000.0

    private let taoyuan = (25.08, 121.23)
    private let miyakoAirport = (24.78, 125.30)
    private let miyakoTown = (24.80, 125.28)
    private let miyakoCape = (24.72, 125.47)

    private func segment(
        _ id: String, from: Double, hours: Double, crossing: Bool = false, points: [(Double, Double)]
    ) -> (segment: SegmentRecord, points: [TrackpointRecord]) {
        let record = SegmentRecord(
            id: id, tripId: "trip", mode: "drive", startedAt: start + from,
            endedAt: start + from + hours * 3600, matchedPolyline: nil, source: "exif",
            routability: crossing ? SegmentRoutability.noRoad.rawValue : SegmentRoutability.road.rawValue
        )
        let trackpoints = points.enumerated().map { index, point in
            TrackpointRecord(segmentId: id, ts: start + from + Double(index), lat: point.0, lon: point.1)
        }
        return (record, trackpoints)
    }

    private func stop(_ id: String, at offset: Double, _ place: (Double, Double)) -> StopRecord {
        StopRecord(
            id: id, tripId: "trip", lat: place.0, lon: place.1,
            arrivedAt: start + offset, departedAt: start + offset + 1800,
            name: nil, note: nil, kind: "dwell"
        )
    }

    /// **The Miyakojima shape**: one photograph at the departure airport, three
    /// days on the island, one photograph at the airport on the way back.
    private var roundTrip: (
        segments: [(segment: SegmentRecord, points: [TrackpointRecord])], stops: [StopRecord]
    ) {
        (
            [
                segment("out", from: 1800, hours: 2, crossing: true, points: [taoyuan, miyakoAirport]),
                segment("d1", from: 3 * 3600, hours: 1, points: [miyakoAirport, miyakoTown]),
                segment("d2", from: day, hours: 2, points: [miyakoTown, miyakoCape]),
                segment("d3", from: 2 * day, hours: 1, points: [miyakoCape, miyakoAirport]),
                segment("back", from: 2 * day + 2 * 3600, hours: 2, crossing: true, points: [miyakoAirport, taoyuan])
            ],
            [
                stop("taoyuan-out", at: 0, taoyuan),
                stop("miyako-arrive", at: 2.5 * 3600, miyakoAirport),
                stop("town", at: 4 * 3600, miyakoTown),
                stop("cape", at: day + 3 * 3600, miyakoCape),
                stop("miyako-leave", at: 2 * day + 3600, miyakoAirport),
                stop("taoyuan-back", at: 2 * day + 4.5 * 3600, taoyuan)
            ]
        )
    }

    func testTheFlightHomeAndTheStopAfterItAreLeftOut() {
        let trip = roundTrip
        let film = RecapComposer.filmRecords(
            segments: trip.segments, stops: trip.stops, epsilonM: 15, matchedEpsilonM: 5, homeRadiusM: 40_000
        )
        XCTAssertEqual(film.segments.map(\.segment.id), ["out", "d1", "d2", "d3"])
        XCTAssertEqual(
            film.stops.map(\.id), ["taoyuan-out", "miyako-arrive", "town", "cape", "miyako-leave"],
            "the film ends on the destination's last stop — the airport it left from"
        )
    }

    /// **Why the cut is by time.** The two Miyakojima airport stops are the same
    /// place, and so are the two Taoyuan ones; "the stop nearest the homecoming"
    /// has two answers on every round trip. The clock has one.
    func testTheSamePlaceVisitedTwiceIsCutByWhenNotWhere() {
        let trip = roundTrip
        let film = RecapComposer.filmRecords(
            segments: trip.segments, stops: trip.stops, epsilonM: 15, matchedEpsilonM: 5, homeRadiusM: 40_000
        )
        XCTAssertTrue(film.stops.contains { $0.id == "taoyuan-out" }, "the departure airport opens the film")
        XCTAssertFalse(film.stops.contains { $0.id == "taoyuan-back" }, "the arrival home does not end it")
    }

    /// End to end through the composer: the trimmed trip is a journey abroad,
    /// and its film has one crossing — the one it opens on.
    func testTheTrimmedTripIsAOneDestinationFilmWithOneCrossing() throws {
        let trip = roundTrip
        let film = RecapComposer.filmRecords(
            segments: trip.segments, stops: trip.stops, epsilonM: 15, matchedEpsilonM: 5, homeRadiusM: 40_000
        )
        let legs = RecapComposer.legs(from: film.segments, epsilonM: 15, matchedEpsilonM: 5)
        XCTAssertEqual(legs.filter(\.isCrossing).count, 1)
        XCTAssertTrue(legs[0].isCrossing, "the film opens on the flight")
        XCTAssertEqual(
            RecapFilmType.classify(
                legs: legs, everyLegEstablished: RecapComposer.everyLegRoutabilityEstablished(film.segments)
            ),
            .oneDestination
        )
    }

    func testATripThatDoesNotComeHomeIsUntouched() {
        let trip = roundTrip
        let oneWay = Array(trip.segments.dropLast())
        let film = RecapComposer.filmRecords(
            segments: oneWay, stops: trip.stops, epsilonM: 15, matchedEpsilonM: 5, homeRadiusM: 40_000
        )
        XCTAssertEqual(film.segments.count, oneWay.count)
        XCTAssertEqual(film.stops.count, trip.stops.count)
    }
}
