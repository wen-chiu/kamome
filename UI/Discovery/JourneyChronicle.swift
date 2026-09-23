import Foundation

/// **What a journey means next to the others** (Chiu, 2026-09-23): which visit
/// to that country it was, and how long the user was home before the next one.
/// Neither fact is in any single journey; both come from reading the timeline
/// as a life rather than a list, which is what separates it from a photo
/// library sorted by trip.
///
/// Pure, so the counting rules are tested without a screen.
enum JourneyChronicle {
    /// "Your 3rd trip to Japan".
    struct Visit: Equatable {
        let ordinal: Int
        let country: String
        /// The visit before this one — "last time: December 2025 (Osaka)".
        /// nil on a first visit.
        var previous: Previous?
    }

    struct Previous: Equatable {
        let startedAt: Double
        let title: String
    }

    /// The visit number of every foreign journey whose country is known, by id.
    ///
    /// - **Home is not a visit.** A journey in the device's region is not
    ///   "your 14th trip to Taiwan"; it gets no line.
    /// - **Overlapping journeys are one visit.** The library can hold the same
    ///   trip twice (imported, then discovered again, or split by a gap), and
    ///   three rows of one Vietnam trip must not read as three trips. A journey
    ///   that starts before an earlier one of that country ended continues its
    ///   visit instead of starting another.
    /// - **Only what Kamome can see is counted.** The number is the visit among
    ///   the journeys on this timeline — which reach back `discovery.lookback_years`
    ///   — not among every trip the user ever took.
    static func visits(_ journeys: [JourneySummary], homeCountryCode: String?) -> [String: Visit] {
        let home = homeCountryCode?.uppercased()
        var count: [String: Int] = [:]
        var lastEnd: [String: Double] = [:]
        // The first journey of the visit in progress, and of the one before it.
        var current: [String: Previous] = [:]
        var before: [String: Previous] = [:]
        var result: [String: Visit] = [:]
        for journey in journeys.sorted(by: { $0.startedAt < $1.startedAt }) {
            guard let code = journey.countryCode?.uppercased(), code != home,
                  let country = journey.countryName, !country.isEmpty
            else { continue }
            if let end = lastEnd[code], journey.startedAt <= end {
                lastEnd[code] = max(end, journey.endedAt)
            } else {
                count[code, default: 0] += 1
                lastEnd[code] = journey.endedAt
                before[code] = current[code]
                current[code] = Previous(startedAt: journey.startedAt, title: journey.headline)
            }
            result[journey.id] = Visit(ordinal: count[code] ?? 1, country: country, previous: before[code])
        }
        return result
    }

    /// Whole days at home between an older journey's end and a newer one's
    /// start, in the current calendar. nil when they touch or overlap — there
    /// was no time at home to speak of.
    static func homeDays(after older: JourneySummary, before newer: JourneySummary) -> Int? {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: Date(timeIntervalSince1970: older.endedAt))
        let to = calendar.startOfDay(for: Date(timeIntervalSince1970: newer.startedAt))
        guard let days = calendar.dateComponents([.day], from: from, to: to).day, days > 1 else { return nil }
        // Both ends were travel days, so the nights at home are one fewer than the gap.
        return days - 1
    }

    /// "2 months", "3 weeks", "5 days" — one unit, the largest that fits, in
    /// the user's locale.
    static func durationText(days: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        formatter.allowedUnits = [.year, .month, .weekOfMonth, .day]
        let reference = Date(timeIntervalSince1970: 0)
        let end = Calendar.current.date(byAdding: .day, value: days, to: reference) ?? reference
        return formatter.string(from: reference, to: end) ?? ""
    }

    /// The pill beside the destination: 「初訪」 / 「第2次」.
    static func pillText(_ visit: Visit) -> String {
        if visit.ordinal == 1 { return String(localized: "journey_visit_pill_first") }
        return String.localizedStringWithFormat(String(localized: "journey_visit_pill_nth"), ordinal(visit.ordinal))
    }

    /// The full sentence, in the expanded entry, where there is room to say
    /// what the count rests on: 「相簿裡第2次到日本」 — the photographs Kamome
    /// can see, not every trip the user ever took.
    static func visitText(_ visit: Visit) -> String {
        if visit.ordinal == 1 {
            return String.localizedStringWithFormat(String(localized: "journey_visit_first"), visit.country)
        }
        return String.localizedStringWithFormat(String(localized: "journey_visit_nth"), ordinal(visit.ordinal), visit.country)
    }

    /// 「上次是 2025年12月（大阪）」. The place is left off when it is only the
    /// country again — 「（日本）」 after 「到日本」 says nothing.
    static func previousText(_ previous: Previous, country: String) -> String {
        let month = DateFormatter()
        month.setLocalizedDateFormatFromTemplate("yMMMM")
        let when = month.string(from: Date(timeIntervalSince1970: previous.startedAt))
        if previous.title == country {
            return String.localizedStringWithFormat(String(localized: "journey_visit_last"), when)
        }
        return String.localizedStringWithFormat(String(localized: "journey_visit_last_place"), when, previous.title)
    }

    private static func ordinal(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .ordinal)
    }
}
