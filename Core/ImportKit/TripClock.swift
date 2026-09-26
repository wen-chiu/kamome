import Foundation

/// **Which local day a moment of a trip fell on, where it happened**
/// (arch review 2026-09-26, round 2 point 2; amends ADR 2026-09-25 §1).
///
/// `TripDay` counted calendar days in the phone's *current* zone. That was
/// accepted for Japan seen from Taipei (the day boundary at 01:00 local), but
/// Iceland seen from Taipei puts it at 16:00, and the same trip exported in
/// Taipei and in Reykjavík drew different `Day N` and a different DAYS figure.
///
/// A day is now the **local date where it happened**: each stop carries the
/// zone its reverse-geocode reported (`stop.time_zone`, schema v14 — the same
/// lookup that names it, so nothing new leaves the phone). A moment at a stop
/// uses that stop's zone; any other moment uses the zone of the stop nearest in
/// time. Day N is that local date minus the local date the trip began on,
/// plus one — so an overnight flight east lands on the next local date, as the
/// traveller lived it.
///
/// **With no zone known** (not yet named, or a trip with no stops) it is
/// exactly the old count in `fallback`, which is the phone's current zone.
public struct TripClock: Equatable {
    public struct StopZone: Equatable {
        public let arrivedAt: Double
        public let departedAt: Double?
        public let zone: TimeZone

        public init(arrivedAt: Double, departedAt: Double?, zone: TimeZone) {
            self.arrivedAt = arrivedAt
            self.departedAt = departedAt
            self.zone = zone
        }
    }

    private let stops: [StopZone]
    private let fallback: TimeZone

    public init(zones: [StopZone], fallback: TimeZone = .current) {
        self.stops = zones.sorted { $0.arrivedAt < $1.arrivedAt }
        self.fallback = fallback
    }

    /// No stop zone known: every moment counts in `zone` — `TripDay`'s rule.
    public static func uniform(_ zone: TimeZone = .current) -> TripClock {
        TripClock(zones: [], fallback: zone)
    }

    /// The zone `timestamp` happened in: the stop it falls within, else the
    /// stop nearest to it in time, else `fallback`.
    public func zone(at timestamp: Double) -> TimeZone {
        var best: (gap: Double, zone: TimeZone)?
        for stop in stops {
            let end = stop.departedAt ?? stop.arrivedAt
            let gap = timestamp < stop.arrivedAt ? stop.arrivedAt - timestamp
                : timestamp > end ? timestamp - end : 0
            if gap == 0 { return stop.zone }
            if best == nil || gap < best!.gap { best = (gap, stop.zone) }
        }
        return best?.zone ?? fallback
    }

    /// 0-based day of `timestamp`: its local date minus the trip's first local
    /// date. Negative before the trip began.
    public func dayIndex(of timestamp: Double, tripStartedAt: Double) -> Int {
        Self.dayNumber(timestamp, in: zone(at: timestamp)) - Self.dayNumber(tripStartedAt, in: zone(at: tripStartedAt))
    }

    /// Local dates the trip covers, both ends counted; never less than 1.
    public func dayCount(startedAt: Double, endedAt: Double) -> Int {
        max(1, dayIndex(of: endedAt, tripStartedAt: startedAt) + 1)
    }

    /// The date day `index` stands for, as a `Date` at local noon **in the
    /// phone's zone** on that calendar date — so formatting it with the
    /// device's own formatter shows the trip's local month and day, whatever
    /// zone the phone is in now. Noon keeps it clear of DST edges.
    public func date(ofDay index: Int, tripStartedAt: Double, displayCalendar: Calendar = .current) -> Date {
        let start = Self.localDate(tripStartedAt, in: zone(at: tripStartedAt))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let firstDay = utc.date(from: start) ?? Date(timeIntervalSince1970: tripStartedAt)
        let target = utc.date(byAdding: .day, value: index, to: firstDay) ?? firstDay
        var parts = utc.dateComponents([.year, .month, .day], from: target)
        parts.hour = 12
        return displayCalendar.date(from: parts) ?? target
    }

    private static func localDate(_ timestamp: Double, in zone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: timestamp))
    }

    /// Days since 1970-01-01 of `timestamp`'s local date in `zone`.
    private static func dayNumber(_ timestamp: Double, in zone: TimeZone) -> Int {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let date = utc.date(from: localDate(timestamp, in: zone)) else { return 0 }
        return Int((date.timeIntervalSince1970 / 86_400).rounded(.down))
    }
}
