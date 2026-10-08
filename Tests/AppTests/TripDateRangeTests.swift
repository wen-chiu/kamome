@testable import Kamome
import KamomeExportEngine
import KamomeImportKit
import KamomePersistence
import KamomeRouteMatching
import XCTest

/// **A trip's date range is the local dates where it began and ended** (#171),
/// on every surface that prints one: the film's title card, Home's row and the
/// merge sheet. `Day N` and the boarding pass already counted that way
/// (`TripClock`); these three formatted in the phone's zone, so a trip that ends
/// in the evening west of the phone printed one date past its own boarding pass.
///
/// The fixture is chosen so that it **discriminates on any host**: both ends
/// fall at 00:30 on Kiritimati (UTC+14), which is the previous date in every
/// zone from UTC−12 to UTC+13. Each test also asserts that the phone-zone
/// reading differs, so a fixture that stopped discriminating fails here
/// instead of passing for the wrong reason.
final class TripDateRangeTests: XCTestCase {
    private let zone = TimeZone(identifier: "Pacific/Kiritimati")!
    /// 2026-03-10 00:30 and 2026-03-12 00:30 on Kiritimati.
    private let startedAt = 1_773_052_200.0
    private let endedAt = 1_773_225_000.0

    private var trip: TripRecord {
        TripRecord(id: "trip-1", title: "Line Islands", startedAt: startedAt, endedAt: endedAt, status: "completed")
    }

    private var stops: [StopRecord] {
        [
            StopRecord(id: "s1", tripId: "trip-1", lat: 1.87, lon: -157.40,
                       arrivedAt: startedAt, departedAt: startedAt + 3600, timeZone: zone.identifier),
            StopRecord(id: "s2", tripId: "trip-1", lat: 1.98, lon: -157.47,
                       arrivedAt: endedAt - 3600, departedAt: endedAt, timeZone: zone.identifier)
        ]
    }

    private var clock: TripClock { TripClock(stops: stops) }

    /// Noon on `day` March 2026 in the phone's calendar: what the phone's own
    /// formatter prints as that date.
    private func march(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: day, hour: 12))!
    }

    func testTheFixtureIsOnTheLocalDatesItClaims() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        XCTAssertEqual(calendar.dateComponents([.month, .day, .hour], from: Date(timeIntervalSince1970: startedAt)),
                       DateComponents(month: 3, day: 10, hour: 0))
        XCTAssertEqual(calendar.dateComponents([.month, .day, .hour], from: Date(timeIntervalSince1970: endedAt)),
                       DateComponents(month: 3, day: 12, hour: 0))
    }

    func testTheTitleCardPrintsTheLocalDates() {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let expected = formatter.string(from: march(10), to: march(12))

        let subtitle = RecapComposer.titleSubtitle(trip: trip, distanceM: nil, clock: clock)

        XCTAssertEqual(subtitle, expected)
        XCTAssertNotEqual(RecapComposer.titleSubtitle(trip: trip, distanceM: nil), expected,
                          "the phone-zone reading must differ, or this fixture proves nothing")
    }

    /// The composer hands the title card the clock it builds from the stops —
    /// the wiring, not just the formatter.
    func testTheComposedFilmCarriesTheLocalDates() throws {
        let points = [(1.87, -157.40), (1.98, -157.47)].enumerated().map { index, point in
            TrackpointRecord(segmentId: "seg-1", ts: startedAt + Double(index) * 60, lat: point.0, lon: point.1)
        }
        let segment = SegmentRecord(id: "seg-1", tripId: "trip-1", mode: "drive",
                                    startedAt: startedAt, endedAt: endedAt, matchedPolyline: nil)
        let recap = try XCTUnwrap(RecapComposer.trip(
            trip: trip,
            legs: RecapComposer.legs(from: [(segment, points)], epsilonM: 15, matchedEpsilonM: 5),
            stops: stops, stats: nil, photosByStop: [:]
        ))

        XCTAssertTrue(recap.subtitle.hasPrefix(RecapComposer.titleSubtitle(trip: trip, distanceM: nil, clock: clock)),
                      "got: \(recap.subtitle)")
    }

    func testHomePrintsTheLocalDates() {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let expected = "\(formatter.string(from: march(10))) – \(formatter.string(from: march(12)))"

        XCTAssertEqual(HomeTripRow.dateRangeText(startedAt: startedAt, endedAt: endedAt, clock: clock), expected)
        XCTAssertNotEqual(HomeTripRow.dateRangeText(startedAt: startedAt, endedAt: endedAt), expected,
                          "the phone-zone reading must differ, or this fixture proves nothing")
    }

    /// A trip that began and ended on one local date prints one date, even
    /// when the phone's zone splits it across two.
    func testHomeCollapsesOneLocalDayToOneDate() {
        let lateEvening = startedAt + 23 * 3600 // 23:30 on Kiritimati, the same date
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        XCTAssertEqual(
            HomeTripRow.dateRangeText(startedAt: startedAt, endedAt: lateEvening, clock: .uniform(zone)),
            formatter.string(from: march(10))
        )
    }

    func testTheMergeSheetPrintsTheLocalDatesAndHours() {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = zone
        let expected = formatter.string(from: Date(timeIntervalSince1970: startedAt),
                                        to: Date(timeIntervalSince1970: endedAt))

        XCTAssertEqual(TripMergeSheet.dateRange(trip, clock: clock), expected)
        XCTAssertNotEqual(TripMergeSheet.dateRange(trip, clock: .uniform()), expected,
                          "the phone-zone reading must differ, or this fixture proves nothing")
    }

    /// A trip that crossed zones prints each end on its own clock.
    func testTheMergeSheetPrintsEachEndOnItsOwnClock() throws {
        let west = try XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu"))
        var crossing = stops
        crossing[1].timeZone = west.identifier

        let text = TripMergeSheet.dateRange(trip, clock: TripClock(stops: crossing))

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = zone
        let from = formatter.string(from: Date(timeIntervalSince1970: startedAt))
        formatter.timeZone = west
        let to = formatter.string(from: Date(timeIntervalSince1970: endedAt))
        XCTAssertEqual(text, "\(from) – \(to)")
    }
}
