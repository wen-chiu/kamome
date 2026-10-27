@testable import Kamome
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeTrackingEngine
import XCTest

/// **A one-day film says no 「第 N 天」** (Chiu 2026-10-26, #295 item 6): every
/// stop would read Day 1. "One day" is the HUD chip's own count — local dates
/// in each stop's zone (ADR 2026-10-01) — never a second rule.
final class RecapComposerDayLabelTests: XCTestCase {
    /// 17:20 UTC — 12:20 in Chicago.
    private let tripStart = 1_752_600_000.0
    private let chicago = "America/Chicago"

    /// The film of a trip `hours` long whose stops arrive `offsets` seconds in,
    /// each stop carrying `chicago` as its geocoded zone. The places are
    /// nowhere in particular: the clock reads only `time_zone`.
    private func film(endingAfter hours: Double, stopsAt offsets: [Double]) throws -> (TripRecord, RecapTrip) {
        let record = TripRecord(
            id: "trip-1", title: "Loop", startedAt: tripStart, endedAt: tripStart + hours * 3_600,
            status: "completed"
        )
        let stops = offsets.enumerated().map { index, offset in
            StopRecord(
                id: "stop-\(index)", tripId: "trip-1", lat: 0, lon: 0,
                arrivedAt: tripStart + offset, departedAt: tripStart + offset + 600,
                name: "Stop \(index)", timeZone: chicago
            )
        }
        let legs = [RecapTrip.Leg(
            coordinates: [RecapCoordinate(lat: 0, lon: 0), RecapCoordinate(lat: 0.1, lon: 0.1)],
            mode: .drive, provenance: .recorded
        )]
        let recap = try XCTUnwrap(RecapComposer.trip(
            trip: record, legs: legs, stops: stops, stats: nil, photosByStop: [:],
            clock: TripClock(stops: stops)
        ))
        return (record, recap)
    }

    /// The clock reads only `time_zone`, so the zone is chosen to differ from
    /// both UTC (CI) and UTC+8 (the desk): a rule counted in either of those
    /// zones gets one of the two trips wrong, and the fixture asserts as much.
    func testAOneDayFilmShowsNoDayAndALongerOneDoes() throws {
        // 12:20 to 23:20 on one Chicago date — two dates in UTC.
        let (oneDay, oneDayFilm) = try film(endingAfter: 11, stopsAt: [600, 10 * 3_600])
        XCTAssertEqual(RecapComposer.dayCount(trip: oneDay, clock: .uniform(TimeZone(identifier: "UTC")!)), 2,
                       "fixture: counted in UTC this trip is two days")
        XCTAssertEqual(oneDayFilm.stops.map(\.dayLabel), ["", ""], "one local day: no stop says which day")

        // 12:20 to 02:20 the next Chicago morning — one date in UTC+8.
        let (twoDays, twoDayFilm) = try film(endingAfter: 14, stopsAt: [600, 13 * 3_600])
        XCTAssertEqual(RecapComposer.dayCount(trip: twoDays, clock: .uniform(TimeZone(identifier: "Asia/Taipei")!)), 1,
                       "fixture: counted in UTC+8 this trip is one day")
        let chicagoClock = TripClock.uniform(TimeZone(identifier: chicago)!)
        XCTAssertEqual(
            twoDayFilm.stops.map(\.dayLabel),
            [600, 13 * 3_600].map {
                RecapComposer.dayLabel(for: tripStart + $0, tripStartedAt: tripStart, clock: chicagoClock)
            },
            "two local days: each stop keeps its Day N"
        )
        XCTAssertNotEqual(twoDayFilm.stops[0].dayLabel, twoDayFilm.stops[1].dayLabel)
    }
}
