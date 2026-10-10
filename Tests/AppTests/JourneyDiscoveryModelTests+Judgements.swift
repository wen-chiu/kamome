@testable import Kamome
import KamomeImportKit
import XCTest

/// Chiu's answers to the 2026-10-09 Footprints walk (#267). Its own file
/// because the test class body is held to 250 lines under SwiftLint.
extension JourneyDiscoveryModelTests {
    /// 4 「count」: hiding a journey does not turn the weeks of it into weeks
    /// at home. The gap under the next journey is measured to the hidden one.
    func testAHomeGapIsMeasuredToAHiddenJourneyToo() async throws {
        let harness = try makeHarness()
        // A third journey between the harness's two (weeks 10 and 30).
        harness.library.photos += (0..<8).map {
            ImportPhoto(assetId: "mid-\($0)", timestamp: 20 * week + Double($0) * 1_800, lat: 48.85, lon: 2.35)
        }
        await harness.model.refresh()
        XCTAssertEqual(harness.model.journeys.count, 3)
        let (newest, middle, oldest) = (harness.model.journeys[0], harness.model.journeys[1], harness.model.journeys[2])
        let toMiddle = try XCTUnwrap(JourneyChronicle.homeDays(after: middle, before: newest))
        let toOldest = try XCTUnwrap(JourneyChronicle.homeDays(after: oldest, before: newest))

        harness.model.hide(middle)
        XCTAssertEqual(harness.model.homeGaps[newest.id], toMiddle, "at home only since the hidden journey")
        XCTAssertNotEqual(toMiddle, toOldest)
        XCTAssertNil(harness.model.homeGaps[middle.id], "a hidden journey has no row")

        harness.model.unhide(try XCTUnwrap(harness.model.hiddenJourneys.first))
        XCTAssertEqual(harness.model.homeGaps[newest.id], toMiddle)
        XCTAssertNotNil(harness.model.homeGaps[middle.id])
    }

    /// 2 「OK」: the diary and the hidden row print the list's form with its
    /// year — one date format for one trip, not `.long` 「2026/8/3至2026/8/5」.
    func testADateRangeWithItsYearNamesTheYearOnce() {
        let start = Date(timeIntervalSince1970: 1_785_000_000) // a day in July 2026, UTC
        let end = start.addingTimeInterval(2 * 86_400)
        let text = JourneyDateText.rangeWithYear(from: start.timeIntervalSince1970, to: end.timeIntervalSince1970)
        let year = String(Calendar.current.component(.year, from: start))
        XCTAssertEqual(text.components(separatedBy: year).count - 1, 1, "the year once, for a range inside one year: \(text)")
        XCTAssertFalse(text.contains("/"), "the month by name, not a numeric date: \(text)")
    }
}
