@testable import Kamome
import KamomePersistence
import KamomeTripComposer
import XCTest

/// **The film's title** (Chiu 2026-09-27): an unnamed trip opens on its
/// country — the card's second line already carries the dates — and a real
/// name is never replaced.
final class TripTitleTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "TripTitleTests"
    private let startedAt = 1_789_900_000.0

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func trip(title: String) -> TripRecord {
        TripRecord(id: "t1", title: title, startedAt: startedAt, status: "completed")
    }

    private func cacheWithJapan() -> JourneyNameCache {
        let cache = JourneyNameCache(defaults: defaults)
        cache.store(PlaceName(country: "Japan", countryCode: "JP", region: nil, locality: nil), for: "t1")
        return cache
    }

    func testAnUnnamedTripsFilmOpensOnItsCountry() {
        let unnamed = trip(title: TripTitle.fallback(for: startedAt))
        XCTAssertEqual(TripTitle.film(unnamed, cache: cacheWithJapan()), "🇯🇵 Japan")
    }

    func testANamedTripKeepsItsName() {
        XCTAssertEqual(TripTitle.film(trip(title: "北海道夏天"), cache: cacheWithJapan()), "北海道夏天")
    }

    // MARK: - The place an unnamed trip is called by (Chiu 2026-10-01)

    private func cache(_ place: PlaceName, singlePlace: Bool, key: String = "t1") -> JourneyNameCache {
        let cache = JourneyNameCache(defaults: defaults)
        cache.store(place, for: key)
        cache.setSinglePlace(singlePlace, for: key)
        return cache
    }

    private let whitehorse = PlaceName(country: "Canada", countryCode: "CA", region: "Yukon", locality: "Whitehorse")
    private let hualien = PlaceName(country: "Taiwan", countryCode: "TW", region: "Hualien County", locality: "Ji'an")

    func testAOneTownTripIsItsFlagAndItsTown() {
        let unnamed = trip(title: TripTitle.fallback(for: startedAt))
        XCTAssertEqual(
            TripTitle.film(unnamed, cache: cache(whitehorse, singlePlace: true), homeCountryCode: "TW"),
            "🇨🇦 Whitehorse"
        )
    }

    func testAWideTripAbroadIsItsCountry() {
        let unnamed = trip(title: TripTitle.fallback(for: startedAt))
        XCTAssertEqual(
            TripTitle.film(unnamed, cache: cache(whitehorse, singlePlace: false), homeCountryCode: "TW"),
            "🇨🇦 Canada"
        )
    }

    /// A wide trip at home is its region on every screen, as it already was on
    /// the Discovery card (ADR 2026-09-17; Chiu 2026-10-01 for Home and the film).
    func testAWideTripAtHomeIsItsRegion() {
        let unnamed = trip(title: TripTitle.fallback(for: startedAt))
        XCTAssertEqual(
            TripTitle.film(unnamed, cache: cache(hualien, singlePlace: false), homeCountryCode: "TW"),
            "🇹🇼 Hualien County"
        )
    }

    func testANeverMeasuredTripReadsAsWide() {
        let cache = JourneyNameCache(defaults: defaults)
        cache.store(whitehorse, for: "t1")
        let unnamed = trip(title: TripTitle.fallback(for: startedAt))
        XCTAssertEqual(TripTitle.film(unnamed, cache: cache, homeCountryCode: "TW"), "🇨🇦 Canada")
    }

    func testSinglePlaceIsRememberedAndForgotten() {
        let cache = JourneyNameCache(defaults: defaults)
        XCTAssertFalse(cache.isSinglePlace("t1"))
        cache.setSinglePlace(true, for: "t1")
        XCTAssertTrue(JourneyNameCache(defaults: defaults).isSinglePlace("t1"))
        cache.setSinglePlace(false, for: "t1")
        XCTAssertFalse(JourneyNameCache(defaults: defaults).isSinglePlace("t1"))
    }

    /// A trip opened from Discovery before #165 was fixed carries the card's
    /// month title. Nobody typed it, so the place names the trip after all —
    /// under its discovery key, where Discovery cached the place.
    func testADiscoveryTripStoredUnderItsMonthIsStillUnnamed() {
        var stuck = trip(title: TripTitle.month(for: startedAt))
        XCTAssertFalse(TripTitle.isFallback(stuck), "a month title someone typed on an ordinary trip is a name")
        stuck.discoveryKey = "2026-09-20"
        XCTAssertTrue(TripTitle.isFallback(stuck))
        XCTAssertEqual(
            TripTitle.film(stuck, cache: cache(whitehorse, singlePlace: true, key: "2026-09-20"), homeCountryCode: "TW"),
            "🇨🇦 Whitehorse"
        )
    }

    func testOneTownIsMeasuredFromTheStops() {
        func stop(_ lat: Double, _ lon: Double) -> StopRecord {
            StopRecord(id: UUID().uuidString, tripId: "t1", lat: lat, lon: lon, arrivedAt: 0, departedAt: 0)
        }
        XCTAssertTrue(TripTitle.isSinglePlace([stop(60.72, -135.05), stop(60.80, -135.20)], under: 60_000))
        XCTAssertFalse(TripTitle.isSinglePlace([stop(35.68, 139.65), stop(35.01, 135.77)], under: 60_000))
        XCTAssertTrue(TripTitle.isSinglePlace([], under: 60_000))
    }

    func testWithoutAPlaceTheStoredTitleStands() {
        let unnamed = trip(title: TripTitle.fallback(for: startedAt))
        XCTAssertEqual(TripTitle.film(unnamed, cache: JourneyNameCache(defaults: defaults)), unnamed.title)
    }

    // MARK: - Unnamed is a stored fact, not a formatted date (#168, Chiu 2026-10-02)

    private func mediumDate(_ locale: String, _ time: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: locale)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: Date(timeIntervalSince1970: time))
    }

    func testAnEmptyTitleIsATripNobodyNamed() {
        let unnamed = trip(title: TripTitle.unnamed)
        XCTAssertTrue(TripTitle.isFallback(unnamed))
        XCTAssertEqual(
            TripTitle.film(unnamed, cache: JourneyNameCache(defaults: defaults)), TripTitle.fallback(for: startedAt),
            "with no place it is called by its start date, never by the blank"
        )
        XCTAssertEqual(TripTitle.film(unnamed, cache: cacheWithJapan()), "🇯🇵 Japan")
        XCTAssertEqual(TripTitle.plain(unnamed), TripTitle.fallback(for: startedAt))
        XCTAssertEqual(TripTitle.plain(trip(title: "北海道夏天")), "北海道夏天")
    }

    /// The bug: the date was compared in today's language, so a title written
    /// under English became a name the day the phone switched to Chinese.
    func testADateWrittenInEitherShippedLanguageIsStillUnnamed() {
        for locale in ["en_US", "zh_Hant_TW"] {
            let written = trip(title: mediumDate(locale, startedAt))
            XCTAssertTrue(TripTitle.isFallback(written), "\(locale): \(written.title)")
            XCTAssertEqual(TripTitle.film(written, cache: cacheWithJapan()), "🇯🇵 Japan")
        }
    }

    /// A phone that has changed time zone since puts the start on the day
    /// before or after the one the title was written from.
    func testADateADayEitherSideIsStillUnnamed() {
        XCTAssertTrue(TripTitle.isFallback(trip(title: mediumDate("en_US", startedAt - 86_400))))
        XCTAssertTrue(TripTitle.isFallback(trip(title: mediumDate("zh_Hant_TW", startedAt + 86_400))))
        XCTAssertFalse(TripTitle.isFallback(trip(title: mediumDate("en_US", startedAt + 3 * 86_400))))
    }

    func testLaunchRewritesOldDateTitlesAndLeavesNames() throws {
        let repository = TripRepository(database: try AppDatabase.inMemory())
        func save(_ title: String) throws -> String {
            try repository.saveCompletedTrip(
                title: title, startedAt: startedAt, endedAt: startedAt + 3_600, segments: [], stops: []
            )
        }
        let english = try save(mediumDate("en_US", startedAt))
        let chinese = try save(mediumDate("zh_Hant_TW", startedAt))
        let named = try save("北海道夏天")

        TripTitle.clearLegacyFallbacks(in: repository)

        XCTAssertEqual(try repository.detail(tripId: english)?.trip.title, TripTitle.unnamed)
        XCTAssertEqual(try repository.detail(tripId: chinese)?.trip.title, TripTitle.unnamed)
        XCTAssertEqual(try repository.detail(tripId: named)?.trip.title, "北海道夏天")
    }

    /// "· 2 km · 0" read as a stray digit (#192): the count carries its unit.
    func testHomesStopCountCarriesItsUnit() {
        let none = HomeView.statsText(TripStats(distanceM: 2_000, driveS: 120, walkS: 0, stopCount: 0, topSpeedKmh: 60))
        let unit = String.localizedStringWithFormat(String(localized: "recap_film_stop_count"), 0)
        XCTAssertTrue(none.hasSuffix(unit), none)
        XCTAssertNotEqual(unit, "0")
    }
}
