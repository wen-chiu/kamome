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
/// resolves, or if it never does, it is called by its start date.
enum TripTitle {
    /// The stored title of a trip nobody named (Chiu 2026-10-02, #168). It used
    /// to be the start date as a string, which only the language and time zone
    /// that wrote it could recognise again.
    static let unnamed = ""

    /// An unnamed trip's start date, in today's language: what it is called
    /// until a place is found for it, or if none ever is.
    static func fallback(for startedAt: Double) -> String {
        formatters[0].date.string(from: Date(timeIntervalSince1970: startedAt))
    }

    /// "March 2026" — what a Discovery card is called until its place is known.
    static func month(for startedAt: Double) -> String {
        formatters[0].month.string(from: Date(timeIntervalSince1970: startedAt))
    }

    /// Nobody named this trip — no album title, never renamed.
    static func isFallback(_ trip: TripRecord) -> Bool {
        trip.title.isEmpty || isLegacyFallback(trip)
    }

    /// The name with no place in it: the real name, or the start date for a
    /// trip nobody named. For the rows that have no place to show.
    static func plain(_ trip: TripRecord) -> String {
        isFallback(trip) ? fallback(for: trip.startedAt) : trip.title
    }

    // MARK: - Titles written before #168

    /// The languages Kamome ships in, with and without the phone's region: the
    /// date string depends on both ("Oct 2, 2026", "2 Oct 2026", "2026年10月2日").
    /// Today's own locale comes first. Built once: Home asks per row.
    private static let formatters: [(date: DateFormatter, month: DateFormatter)] = {
        let region = Locale.current.region?.identifier
        let identifiers = ["en", "en_US", "zh-Hant", "zh_Hant_TW"]
            + (region.map { ["en_\($0)", "zh_Hant_\($0)"] } ?? [])
        return ([Locale.current] + identifiers.map(Locale.init(identifier:))).map { locale in
            let date = DateFormatter()
            date.locale = locale
            date.dateStyle = .medium
            date.timeStyle = .none
            let month = DateFormatter()
            month.locale = locale
            month.setLocalizedDateFormatFromTemplate("yMMMM")
            return (date, month)
        }
    }()

    /// A title written before #168: the start date in a language Kamome ships
    /// in, or a day either side of it for a phone that has changed time zone
    /// since. A trip opened from Discovery before #165 carries the card's month
    /// the same way. Nobody typed either.
    static func isLegacyFallback(_ trip: TripRecord) -> Bool {
        let days = [-86_400.0, 0, 86_400].map { Date(timeIntervalSince1970: trip.startedAt + $0) }
        return formatters.contains { formatter in
            days.contains { formatter.date.string(from: $0) == trip.title }
                || (trip.discoveryKey != nil && days.contains { formatter.month.string(from: $0) == trip.title })
        }
    }

    /// Rewrites every title `isLegacyFallback` recognises as `unnamed`, so the
    /// store says "nobody named this" as a fact. Run at launch; a store with
    /// none left is one read.
    static func clearLegacyFallbacks(in repository: TripRepository) {
        let trips = Stored.read("allTrips") { try repository.allTrips() } ?? []
        for trip in trips where !trip.title.isEmpty && isLegacyFallback(trip) {
            Stored.write("setTripTitle") { try repository.setTripTitle(tripId: trip.id, title: unnamed) }
        }
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

    /// The flag of the place found for the trip, for a row that shows a real
    /// name beside it as Footprints does. nil until a lookup resolves.
    static func flag(
        for trip: TripRecord,
        cache: JourneyNameCache = JourneyNameCache(),
        homeCountryCode: String? = JourneyNameCache.deviceHomeCountryCode
    ) -> String? {
        let key = placeKey(for: trip)
        return cache.name(for: key, homeCountryCode: homeCountryCode, isSinglePlace: cache.isSinglePlace(key))?.flag
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
        return place(for: trip, cache: cache, homeCountryCode: homeCountryCode) ?? fallback(for: trip.startedAt)
    }
}
