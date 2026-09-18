@testable import Kamome
import XCTest

/// **What a journey is called** — the pure half of naming, with no geocoder.
final class JourneyNamingTests: XCTestCase {
    private let taiwan = PlaceName(country: "Taiwan", countryCode: "TW", region: "Taipei City", locality: "Taipei")

    func testAJourneyInOnePlaceIsNamedAfterTheTown() {
        let whitehorse = PlaceName(country: "Canada", countryCode: "CA", region: "Yukon", locality: "Whitehorse")
        let name = JourneyNaming.name(place: whitehorse, home: taiwan, isSinglePlace: true)
        XCTAssertEqual(name?.title, "Whitehorse")
        XCTAssertEqual(name?.flag, "🇨🇦")
    }

    func testAJourneyAcrossACountryIsNamedAfterTheCountry() {
        let tokyo = PlaceName(country: "Japan", countryCode: "JP", region: "Tokyo", locality: "Shibuya")
        let name = JourneyNaming.name(place: tokyo, home: taiwan, isSinglePlace: false)
        XCTAssertEqual(name?.title, "Japan")
        XCTAssertEqual(name?.flag, "🇯🇵")
    }

    /// A domestic road trip named after the home country says nothing; the
    /// region is the destination.
    func testADomesticJourneyIsNamedAfterTheRegion() {
        let hualien = PlaceName(country: "Taiwan", countryCode: "TW", region: "Hualien County", locality: "Hualien City")
        XCTAssertEqual(JourneyNaming.name(place: hualien, home: taiwan, isSinglePlace: false)?.title, "Hualien County")
        XCTAssertEqual(JourneyNaming.name(place: hualien, home: taiwan, isSinglePlace: true)?.title, "Hualien City")
    }

    func testMissingFieldsFallThroughRatherThanFailing() {
        let sparse = PlaceName(country: "Iceland", countryCode: "IS", region: nil, locality: nil)
        XCTAssertEqual(JourneyNaming.name(place: sparse, home: nil, isSinglePlace: true)?.title, "Iceland")
        let nothing = PlaceName(country: nil, countryCode: nil, region: nil, locality: nil)
        XCTAssertNil(JourneyNaming.name(place: nothing, home: nil, isSinglePlace: true))
    }

    func testTheFlagComesOnlyFromATwoLetterCode() {
        XCTAssertEqual(JourneyNaming.flag(countryCode: "nz"), "🇳🇿")
        XCTAssertEqual(JourneyNaming.flag(countryCode: "FI"), "🇫🇮")
        XCTAssertNil(JourneyNaming.flag(countryCode: nil))
        XCTAssertNil(JourneyNaming.flag(countryCode: "NZL"))
        XCTAssertNil(JourneyNaming.flag(countryCode: "1A"))
    }

    /// Places round-trip through the on-device cache, and the **name is derived
    /// on read**: a journey that widens after it was looked up is renamed from
    /// the cached place without asking again. The cache holds places only — it
    /// is keyed by journey, never by position (§0).
    func testTheCacheHoldsPlacesAndDerivesTheNameOnRead() throws {
        let suite = "kamome.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cache = JourneyNameCache(defaults: defaults)

        XCTAssertNil(cache.place(for: "journey-1"))
        XCTAssertNil(cache.name(for: "journey-1", isSinglePlace: true))
        let rome = PlaceName(country: "Italy", countryCode: "IT", region: "Lazio", locality: "Rome")
        cache.store(rome, for: "journey-1")
        XCTAssertEqual(cache.place(for: "journey-1"), rome)
        XCTAssertEqual(cache.name(for: "journey-1", isSinglePlace: true), JourneyName(title: "Rome", flag: "🇮🇹"))
        XCTAssertEqual(cache.name(for: "journey-1", isSinglePlace: false)?.title, "Italy", "widened → the country")

        XCTAssertNil(cache.home())
        cache.storeHome(PlaceName(country: "Italy", countryCode: "IT", region: "Lombardy", locality: "Milan"))
        XCTAssertEqual(cache.home()?.countryCode, "IT")
        XCTAssertEqual(cache.name(for: "journey-1", isSinglePlace: false)?.title, "Lazio", "and at home → the region")
    }
}
