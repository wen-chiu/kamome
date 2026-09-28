import Foundation
import KamomePersistence

/// What a trip is called on screen and in its film — one rule for Home, the
/// story screen and the film's title and end cards (Chiu 2026-09-27).
///
/// A real name always wins: an album's, a Discovery card's, or one the person
/// typed. Only a trip still carrying its plain start-date title — nobody named
/// it — is called by the place `TripJourneyNaming` found for it (flag +
/// country). Until that one-time lookup resolves, or if it never does, the
/// stored title stands.
enum TripTitle {
    /// The title a trip is given when nobody names it: its start date.
    static func fallback(for startedAt: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: startedAt))
    }

    /// Nobody named this trip — no album title, no Discovery card, never renamed.
    static func isFallback(_ trip: TripRecord) -> Bool {
        trip.title == fallback(for: trip.startedAt)
    }

    /// "🇯🇵 Japan": the place cached at trip creation — the same cache Journey
    /// Discovery writes. First stop's country only (§0 scope, see
    /// `TripJourneyNaming`); nil until the lookup resolves or if it never finds one.
    static func place(for trip: TripRecord, cache: JourneyNameCache = JourneyNameCache()) -> String? {
        guard let place = cache.place(for: trip.discoveryKey ?? trip.id),
              let country = place.country
        else { return nil }
        let flag = JourneyNaming.flag(countryCode: place.countryCode)
        return [flag, country].compactMap { $0 }.joined(separator: " ")
    }

    /// The film's title: the real name, or the place for an unnamed trip. The
    /// dates are already the title card's second line, so an unnamed trip no
    /// longer prints its date twice.
    static func film(_ trip: TripRecord, cache: JourneyNameCache = JourneyNameCache()) -> String {
        guard isFallback(trip) else { return trip.title }
        return place(for: trip, cache: cache) ?? trip.title
    }
}
