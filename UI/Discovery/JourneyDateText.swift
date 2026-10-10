import Foundation

// Moved out of JourneyEntry.swift as written (2026-10-07) when that file
// passed SwiftLint's 400 lines.

/// Compact, locale-aware date ranges for timeline anchors: "3 – 5 Aug" inside
/// one month, "28 Aug – 2 Sep" across two. The year is deliberately absent —
/// the section heading above already carries it.
enum JourneyDateText {
    static func range(from startedAt: Double, to endedAt: Double) -> String {
        let start = Date(timeIntervalSince1970: startedAt)
        let end = Date(timeIntervalSince1970: endedAt)
        let calendar = Calendar.current
        if calendar.isDate(start, equalTo: end, toGranularity: .day) {
            return dayAndMonth.string(from: start)
        }
        if calendar.isDate(start, equalTo: end, toGranularity: .month) {
            // The month sits on the opening date and the range runs from it —
            // "Aug 3 – 5". Putting it on the closing date reads as a typo.
            return "\(dayAndMonth.string(from: start)) – \(dayOnly.string(from: end))"
        }
        return "\(dayAndMonth.string(from: start)) – \(dayAndMonth.string(from: end))"
    }

    /// The same range with its year, for a screen with no year heading above
    /// it — the diary's masthead and the hidden row (Chiu 2026-10-10, #267:
    /// one trip printed in four date formats). The locale's own interval form
    /// of day, month and year: "Aug 3 – 5, 2026", 「2026年8月3日至5日」.
    static func rangeWithYear(from startedAt: Double, to endedAt: Double) -> String {
        withYear.string(from: Date(timeIntervalSince1970: startedAt), to: Date(timeIntervalSince1970: endedAt))
    }

    private static let withYear: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateTemplate = "yMMMd"
        return formatter
    }()

    private static let dayAndMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter
    }()

    private static let dayOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()
}
