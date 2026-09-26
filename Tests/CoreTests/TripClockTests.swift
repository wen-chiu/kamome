import KamomeImportKit
import XCTest

/// **A day is the local date where it happened** (arch review 2026-09-26,
/// amending ADR 2026-09-25 §1). Counting in the phone's current zone put an
/// Iceland trip's day boundary at 16:00 local when read in Taipei, and made the
/// same trip draw different days depending on where the phone was at export.
final class TripClockTests: XCTestCase {
    private let reykjavik = TimeZone(identifier: "Atlantic/Reykjavik")!
    private let taipei = TimeZone(identifier: "Asia/Taipei")!
    private let auckland = TimeZone(identifier: "Pacific/Auckland")!

    /// 2026-08-10 09:00 in Reykjavík (UTC+0).
    private let icelandMorning = 1_786_352_400.0

    private func iceland(fallback: TimeZone) -> TripClock {
        TripClock(zones: [
            .init(arrivedAt: icelandMorning, departedAt: icelandMorning + 3_600, zone: reykjavik),
            .init(arrivedAt: icelandMorning + 2 * 86_400, departedAt: nil, zone: reykjavik)
        ], fallback: fallback)
    }

    func testAnIcelandEveningIsStillDayOneWhenReadFromTaipei() {
        // 18:00 the same day in Reykjavík is 02:00 the next day in Taipei — the
        // old count called it Day 2.
        let evening = icelandMorning + 9 * 3_600
        XCTAssertEqual(iceland(fallback: taipei).dayIndex(of: evening, tripStartedAt: icelandMorning), 0)
        XCTAssertEqual(TripDay.index(of: evening, tripStartedAt: icelandMorning, calendar: {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = taipei; return calendar
        }()), 1, "precondition: the phone-zone count really did split this day")
    }

    func testTheSameTripCountsTheSameWhereverThePhoneIs() {
        let end = icelandMorning + 2 * 86_400 + 10 * 3_600
        let fromTaipei = iceland(fallback: taipei).dayCount(startedAt: icelandMorning, endedAt: end)
        let fromReykjavik = iceland(fallback: reykjavik).dayCount(startedAt: icelandMorning, endedAt: end)
        XCTAssertEqual(fromTaipei, 3)
        XCTAssertEqual(fromTaipei, fromReykjavik)
    }

    func testAnOvernightFlightEastLandsOnTheNextLocalDate() {
        // Leave Taipei 2026-02-01 23:00 (+8), land Auckland 2026-02-02 15:00 (+13).
        let departure = 1_769_958_000.0
        let arrival = departure + 11 * 3_600
        let clock = TripClock(zones: [
            .init(arrivedAt: departure - 3_600, departedAt: departure, zone: taipei),
            .init(arrivedAt: arrival, departedAt: arrival + 3_600, zone: auckland)
        ])
        XCTAssertEqual(clock.dayIndex(of: arrival, tripStartedAt: departure - 3_600), 1)
    }

    func testWithNoZoneKnownItIsThePhoneZoneCount() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = taipei
        for offset in stride(from: -3_600.0, through: 5 * 86_400, by: 3_917) {
            XCTAssertEqual(
                TripClock.uniform(taipei).dayIndex(of: icelandMorning + offset, tripStartedAt: icelandMorning),
                TripDay.index(of: icelandMorning + offset, tripStartedAt: icelandMorning, calendar: calendar)
            )
        }
    }

    func testTheDateOfADayShowsTheLocalCalendarDate() {
        var phone = Calendar(identifier: .gregorian)
        phone.timeZone = taipei
        let day2 = iceland(fallback: taipei).date(ofDay: 1, tripStartedAt: icelandMorning, displayCalendar: phone)
        let parts = phone.dateComponents([.month, .day], from: day2)
        XCTAssertEqual(parts.month, 8)
        XCTAssertEqual(parts.day, 11, "Day 2 of a trip that began 8/10 in Reykjavík is 8/11, read anywhere")
    }
}
