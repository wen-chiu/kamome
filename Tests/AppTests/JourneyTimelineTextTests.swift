@testable import Kamome
import XCTest

/// **What the timeline says when there are no photographs to look at** — the
/// date anchor and the route line, which are the two things carrying a journey
/// on Home once the images are covered up (2026-09-18 redesign).
final class JourneyTimelineTextTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))?
            .timeIntervalSince1970 ?? 0
    }

    /// **The month belongs to the opening date.** The first render of this row
    /// printed "3 – Aug 5", which reads as a typo rather than a range.
    func testARangeInsideOneMonthNamesTheMonthOnce() {
        let text = JourneyDateText.range(from: date(2026, 8, 3), to: date(2026, 8, 5))
        XCTAssertTrue(text.contains("3"), text)
        XCTAssertTrue(text.contains("5"), text)
        XCTAssertTrue(text.contains("–"), text)
        // The month is named, and only once.
        let months = text.components(separatedBy: "Aug").count - 1
        XCTAssertEqual(months, 1, "one month name for a range inside one month: \(text)")
        XCTAssertTrue(text.hasPrefix("Aug"), "the month opens the range: \(text)")
    }

    func testARangeAcrossTwoMonthsNamesBoth() {
        let text = JourneyDateText.range(from: date(2026, 8, 28), to: date(2026, 9, 2))
        XCTAssertTrue(text.contains("Aug"), text)
        XCTAssertTrue(text.contains("Sep"), text)
    }

    func testASingleDayIsNotDrawnAsARange() {
        let text = JourneyDateText.range(from: date(2026, 8, 3), to: date(2026, 8, 3))
        XCTAssertFalse(text.contains("–"), "one day is one date: \(text)")
        XCTAssertTrue(text.contains("Aug"), text)
    }

    /// **The year is never in the anchor**: the section heading above it is the
    /// year, and repeating it on every entry is what made the row a caption.
    func testTheAnchorLeavesTheYearToTheSectionHeading() {
        for text in [
            JourneyDateText.range(from: date(2026, 8, 3), to: date(2026, 8, 5)),
            JourneyDateText.range(from: date(2025, 12, 30), to: date(2026, 1, 2))
        ] {
            XCTAssertFalse(text.contains("2026"), text)
            XCTAssertFalse(text.contains("2025"), text)
        }
    }

    /// Three stops around one town all geocode to "Whitehorse", and the first
    /// render printed it three times joined by cars. The stops are still three;
    /// only the naming repeats, so only the naming collapses.
    func testRepeatedPlaceNamesCollapseButDistinctOnesDoNot() {
        XCTAssertEqual(
            JourneyRouteText.collapsingRepeats(["Whitehorse", "Whitehorse", "Whitehorse Airport"]),
            ["Whitehorse", "Whitehorse Airport"]
        )
        XCTAssertEqual(
            JourneyRouteText.collapsingRepeats(["Tokyo", "Hakone", "Kyoto"]),
            ["Tokyo", "Hakone", "Kyoto"]
        )
        // Only *consecutive* repeats collapse — coming back is part of the story.
        XCTAssertEqual(
            JourneyRouteText.collapsingRepeats(["Kyoto", "Nara", "Kyoto"]),
            ["Kyoto", "Nara", "Kyoto"]
        )
        XCTAssertEqual(JourneyRouteText.collapsingRepeats([]), [])
    }
}
