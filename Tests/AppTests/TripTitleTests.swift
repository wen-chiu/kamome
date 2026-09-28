@testable import Kamome
import KamomePersistence
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

    func testWithoutAPlaceTheStoredTitleStands() {
        let unnamed = trip(title: TripTitle.fallback(for: startedAt))
        XCTAssertEqual(TripTitle.film(unnamed, cache: JourneyNameCache(defaults: defaults)), unnamed.title)
    }
}
