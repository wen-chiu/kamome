import Foundation
import KamomePersistence
import KamomeTrackingEngine

/// What a trip is called on screen and in its film — one rule for Home, Trip
/// Detail, the Discovery list, the diary and the film's title and end cards
/// (Chiu 2026-09-27, 2026-10-01).
///
/// A real name always wins: an album's, or one the person typed. A trip nobody
/// named is called by the place found for it, by `JourneyNaming`'s rule and
/// with its flag: the town for a trip that stayed in one place, the region for
/// a wider trip at home, the country for one abroad. Until that lookup
/// resolves, or if it never does, the stored title stands.
enum TripTitle {
    /// The title a trip is given when nobody names it: its start date.
    static func fallback(for startedAt: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: startedAt))
    }

    /// "March 2026" — what a Discovery card is called until its place is known.
    static func month(for startedAt: Double) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: Date(timeIntervalSince1970: startedAt))
    }

    /// Nobody named this trip — no album title, never renamed.
    ///
    /// A trip opened from Discovery before its place was known used to be
    /// stored under the card's month title (#165). Nobody typed that either,
    /// so it counts as unnamed and the trip is called by its place once found.
    static func isFallback(_ trip: TripRecord) -> Bool {
        if trip.title == fallback(for: trip.startedAt) { return true }
        return trip.discoveryKey != nil && trip.title == month(for: trip.startedAt)
    }

    /// The key a trip's place is cached under — the same one Discovery writes.
    static func placeKey(for trip: TripRecord) -> String {
        trip.discoveryKey ?? trip.id
    }

    /// Whether these stops stayed in one place: their bounding box's diagonal
    /// is under `discovery.single_place_extent_m`.
    static func isSinglePlace(_ stops: [StopRecord], under extentM: Double) -> Bool {
        let lats = stops.map(\.lat)
        let lons = stops.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max()
        else { return true }
        return Geo.distanceM(latA: minLat, lonA: minLon, latB: maxLat, lonB: maxLon) < extentM
    }

    /// "🇨🇦 Whitehorse", "🇹🇼 花蓮縣", "🇯🇵 Japan": the place cached for the trip,
    /// named by `JourneyNaming`'s rule. nil until a lookup resolves or if none
    /// ever does. Whether the trip stayed in one place is read from the cache,
    /// where creation and Trip Detail record it.
    static func place(
        for trip: TripRecord,
        cache: JourneyNameCache = JourneyNameCache(),
        homeCountryCode: String? = JourneyNameCache.deviceHomeCountryCode
    ) -> String? {
        let key = placeKey(for: trip)
        guard let name = cache.name(
            for: key, homeCountryCode: homeCountryCode, isSinglePlace: cache.isSinglePlace(key)
        ) else { return nil }
        return [name.flag, name.title].compactMap { $0 }.joined(separator: " ")
    }

    /// The trip's name wherever it is shown or filmed: the real name, or the
    /// place for an unnamed trip. The dates are already the title card's second
    /// line, so an unnamed trip does not print its date twice.
    static func film(
        _ trip: TripRecord,
        cache: JourneyNameCache = JourneyNameCache(),
        homeCountryCode: String? = JourneyNameCache.deviceHomeCountryCode
    ) -> String {
        guard isFallback(trip) else { return trip.title }
        return place(for: trip, cache: cache, homeCountryCode: homeCountryCode) ?? trip.title
    }
}
