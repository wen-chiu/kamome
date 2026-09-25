import XCTest

@testable import KamomeImportKit

/// **"Day N" is a calendar day** (Chiu 2026-09-25). The Japan import began in
/// the afternoon, so 24-hour blocks from the first photograph put every
/// morning stop into the previous day's chip.
final class TripDayTests: XCTestCase {
    private var taipei: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }

    /// 2026-08-22 15:00 in Taipei.
    private let start = 1_787_382_000.0

    func testTheNextMorningIsTheNextDay() {
        let nextMorning = start + 18 * 3_600 // 2026-08-23 09:00, 18 h in
        XCTAssertEqual(TripDay.index(of: nextMorning, tripStartedAt: start, calendar: taipei), 1,
                       "24-hour blocks said 0 here — the defect")
        XCTAssertEqual(TripDay.index(of: start + 8 * 3_600, tripStartedAt: start, calendar: taipei), 0,
                       "23:00 the same evening is still Day 1")
    }

    func testTheFifthDateIsDayFive() {
        let morningOfTheFifthDate = start + 4 * 86_400 - 6 * 3_600 // 2026-08-26 09:00
        XCTAssertEqual(TripDay.index(of: morningOfTheFifthDate, tripStartedAt: start, calendar: taipei) + 1, 5)
    }

    func testCountIsDatesCoveredBothEndsCounted() {
        XCTAssertEqual(TripDay.count(startedAt: start, endedAt: start, calendar: taipei), 1)
        XCTAssertEqual(TripDay.count(startedAt: start, endedAt: start + 18 * 3_600, calendar: taipei), 2,
                       "an overnight covers two dates though it is under 24 hours")
        XCTAssertEqual(TripDay.count(startedAt: start, endedAt: start - 60, calendar: taipei), 1, "never below 1")
    }

    func testTheDateOfADayIsItsMidnight() {
        let day4 = TripDay.date(ofDay: 4, tripStartedAt: start, calendar: taipei)
        let parts = taipei.dateComponents([.month, .day, .hour, .minute], from: day4)
        XCTAssertEqual([parts.month, parts.day, parts.hour, parts.minute], [8, 26, 0, 0])
    }
}
