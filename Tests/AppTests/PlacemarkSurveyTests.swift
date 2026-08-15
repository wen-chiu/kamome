import CoreLocation
@testable import Kamome
import KamomeConfig
import KamomeImportKit
import KamomePersistence
import KamomeTripComposer
import XCTest

/// TEMPORARY survey (2026-08-05): what `CLPlacemark` actually returns for a real
/// trip's stops, and whether asking for a Chinese locale is free.
///
/// Answers two questions with evidence instead of guesswork:
/// 1. Is there a landmark/POI name available that `StopDisplayName` is not using?
/// 2. Does `reverseGeocodeLocation(_:preferredLocale:)` localise for free, or does
///    a Chinese name need a separate translation service?
///
/// Coordinates are never printed (CLAUDE.md §0) — only the fields Apple returns.
///
///     TEST_RUNNER_KAMOME_PLACEMARK_SURVEY=iceland …
final class PlacemarkSurveyTests: XCTestCase {
    func testSurveyPlacemarkFields() async throws {
        let fixture = HarnessEnv.value("KAMOME_PLACEMARK_SURVEY") ?? ""
        try XCTSkipUnless(!fixture.isEmpty, "Manual survey — set KAMOME_PLACEMARK_SURVEY.")
        let limit = HarnessEnv.value("KAMOME_PLACEMARK_LIMIT")
            .flatMap(Int.init) ?? 12

        let config = AppConfig.loadOrDie()
        let repository = TripRepository(database: try AppDatabase.inMemory())
        let service = ImportService(repository: repository, config: config)
        let trip = try RecapDemoFilmTests.tripFixture(named: fixture)
        let tripId = try await service.importTrip(title: trip.title, photos: trip.photos)
        let stops = try XCTUnwrap(try repository.detail(tripId: tripId)).stops

        // The most-photographed stops: the ones most likely to be real landmarks,
        // and the ones a viewer will actually read on a card.
        let photos = try XCTUnwrap(try repository.detail(tripId: tripId)).photos
        let ranked = stops
            .map { stop in (stop, photos.filter { $0.stopId == stop.id }.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)

        let geocoder = CLGeocoder()
        let zh = Locale(identifier: "zh-Hant")
        for (index, entry) in ranked.enumerated() {
            let location = CLLocation(latitude: entry.0.lat, longitude: entry.0.lon)
            let base = try? await geocoder.reverseGeocodeLocation(location).first
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let localized = try? await geocoder.reverseGeocodeLocation(
                location, preferredLocale: zh
            ).first
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            print("""
            KAMOME_PLACEMARK #\(index) (\(entry.1) photos)
              name            \(base?.name ?? "—")
              areasOfInterest \(base?.areasOfInterest?.joined(separator: " / ") ?? "—")
              thoroughfare    \(base?.thoroughfare ?? "—")
              subLocality     \(base?.subLocality ?? "—")
              locality        \(base?.locality ?? "—")
              subAdminArea    \(base?.subAdministrativeArea ?? "—")
              adminArea       \(base?.administrativeArea ?? "—")
              country         \(base?.country ?? "—")
              inlandWater     \(base?.inlandWater ?? "—")
              CURRENT PICK    \(StopDisplayName.choose(
                  name: base?.name, thoroughfare: base?.thoroughfare,
                  subLocality: base?.subLocality, locality: base?.locality,
                  administrativeArea: base?.administrativeArea, country: base?.country,
                  inlandWater: base?.inlandWater, ocean: base?.ocean
              ) ?? "nil")
              zh-Hant name    \(localized?.name ?? "—")
              zh-Hant locality \(localized?.locality ?? "—")
              zh-Hant country \(localized?.country ?? "—")
            """)
        }
    }
}
