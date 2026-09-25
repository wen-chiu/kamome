import Foundation

/// **What "Day N" of a trip means** — one definition for S3's chips, the diary,
/// the Discovery card and the film's HUD and end card (Chiu 2026-09-25).
///
/// A day is a **calendar day** in `calendar`'s zone: Day 1 is the date the trip
/// started on, and a photograph taken on the fifth date is on Day 5, whatever
/// hour the first photograph was taken at. It replaces elapsed 24-hour blocks
/// from the first photograph, which put a morning stop into the previous "day"
/// whenever the trip began in the afternoon (the Japan import, 2026-09-24).
///
/// The zone is the phone's current one by default. A photograph's own zone is
/// not known (`ImportPhoto` carries an instant, not a wall clock), so a trip
/// one hour east of home reads its day boundary at 01:00 local — accepted.
public enum TripDay {
    /// 0-based: the calendar days between the trip's first date and
    /// `timestamp`'s date. Negative for an instant before the trip began.
    public static func index(of timestamp: Double, tripStartedAt: Double, calendar: Calendar = .current) -> Int {
        let from = calendar.startOfDay(for: Date(timeIntervalSince1970: tripStartedAt))
        let to = calendar.startOfDay(for: Date(timeIntervalSince1970: timestamp))
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// Calendar dates the trip covers, both ends counted; never less than 1.
    public static func count(startedAt: Double, endedAt: Double, calendar: Calendar = .current) -> Int {
        max(1, index(of: endedAt, tripStartedAt: startedAt, calendar: calendar) + 1)
    }

    /// Midnight at the start of day `index` (0-based).
    public static func date(ofDay index: Int, tripStartedAt: Double, calendar: Calendar = .current) -> Date {
        let first = calendar.startOfDay(for: Date(timeIntervalSince1970: tripStartedAt))
        return calendar.date(byAdding: .day, value: index, to: first) ?? first
    }
}
